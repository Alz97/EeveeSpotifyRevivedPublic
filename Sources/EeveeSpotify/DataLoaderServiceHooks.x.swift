import Foundation
import Orion
import os

// MARK: - Thread‑safe token storage
private struct TokenStorage {
    private static var _spotifyAccessToken: String?
    private static var tokenLock = os_unfair_lock_s()
    
    static var spotifyAccessToken: String? {
        get {
            os_unfair_lock_lock(&tokenLock)
            defer { os_unfair_lock_unlock(&tokenLock) }
            return _spotifyAccessToken
        }
        set {
            os_unfair_lock_lock(&tokenLock)
            defer { os_unfair_lock_unlock(&tokenLock) }
            _spotifyAccessToken = newValue
        }
    }
}

// Esponiamo la variabile pubblica tramite un computed property
public var spotifyAccessToken: String? {
    get { TokenStorage.spotifyAccessToken }
    set { TokenStorage.spotifyAccessToken = newValue }
}

class SPTDataLoaderServiceHook: ClassHook<NSObject>, SpotifySessionDelegate {
    static let targetName = "SPTDataLoaderService"

    // Thread-safe cache for modified /customize response
    private static var _cachedCustomizeData: Data?
    static var cachedCustomizeData: Data? {
        get {
            os_unfair_lock_lock(&customizeLock)
            defer { os_unfair_lock_unlock(&customizeLock) }
            return _cachedCustomizeData
        }
        set {
            os_unfair_lock_lock(&customizeLock)
            defer { os_unfair_lock_unlock(&customizeLock) }
            _cachedCustomizeData = newValue
        }
    }
    private static var customizeLock = os_unfair_lock_s()

    // Tasks for which we already handled a 304 on /customize
    private static var _handledCustomizeTasks = Set<Int>()
    private static var handledCustomizeTasks: Set<Int> {
        get {
            os_unfair_lock_lock(&tasksLock)
            defer { os_unfair_lock_unlock(&tasksLock) }
            return _handledCustomizeTasks
        }
        set {
            os_unfair_lock_lock(&tasksLock)
            defer { os_unfair_lock_unlock(&tasksLock) }
            _handledCustomizeTasks = newValue
        }
    }
    private static var tasksLock = os_unfair_lock_s()

    // Tasks for which we already replaced lyrics (avoid double processing)
    private static var _handledLyricsTasks = Set<Int>()
    private static var handledLyricsTasks: Set<Int> {
        get {
            os_unfair_lock_lock(&lyricsLock)
            defer { os_unfair_lock_unlock(&lyricsLock) }
            return _handledLyricsTasks
        }
        set {
            os_unfair_lock_lock(&lyricsLock)
            defer { os_unfair_lock_unlock(&lyricsLock) }
            _handledLyricsTasks = newValue
        }
    }
    private static var lyricsLock = os_unfair_lock_s()

    // Fake responses for blocked endpoints (consolidated)
    private static let emptyData = Data()
    private static let accountValidationResponse = "{\"status\":1,\"country\":\"IT\",\"is_country_launched\":true}".data(using: .utf8)!
    private static let trialsFacadeResponse = "{\"result\":\"NOT_ELIGIBLE\"}".data(using: .utf8)!
    private static let premiumMarketingResponse = "{}".data(using: .utf8)!

    // MARK: - URL filtering
    func shouldBlock(_ url: URL) -> Bool {
        return url.isDeleteToken || url.isAccountValidate || url.isOndemandSelector
            || url.isTrialsFacade || url.isPremiumMarketing || url.isPendragonFetchMessageList
            || url.isSessionInvalidation || url.isPushkaTokens
    }

    func shouldModify(_ url: URL) -> Bool {
        let shouldPatchPremium = BasePremiumPatchingGroup.isActive
        let shouldReplaceLyrics = BaseLyricsGroup.isActive

        return (shouldReplaceLyrics && url.isLyrics)
            || (shouldPatchPremium && (url.isCustomize || url.isPremiumPlanRow || url.isPremiumBadge || url.isPlanOverview))
    }

    // MARK: - Helper to send custom data
    func respondWithCustomData(_ data: Data, task: URLSessionDataTask, session: URLSession) {
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }

    // MARK: - Blocked endpoint handling
    func handleBlockedEndpoint(_ url: URL, task: URLSessionDataTask, session: URLSession) {
        if url.isDeleteToken {
            respondWithCustomData(SPTDataLoaderServiceHook.emptyData, task: task, session: session)
        } else if url.isAccountValidate {
            respondWithCustomData(SPTDataLoaderServiceHook.accountValidationResponse, task: task, session: session)
        } else if url.isOndemandSelector {
            respondWithCustomData(SPTDataLoaderServiceHook.emptyData, task: task, session: session)
        } else if url.isTrialsFacade {
            respondWithCustomData(SPTDataLoaderServiceHook.trialsFacadeResponse, task: task, session: session)
        } else if url.isPremiumMarketing {
            respondWithCustomData(SPTDataLoaderServiceHook.premiumMarketingResponse, task: task, session: session)
        } else if url.isPendragonFetchMessageList {
            respondWithCustomData(SPTDataLoaderServiceHook.emptyData, task: task, session: session)
        } else if url.isPushkaTokens {
            respondWithCustomData(SPTDataLoaderServiceHook.emptyData, task: task, session: session)
        } else if url.isSessionInvalidation {
            respondWithCustomData(SPTDataLoaderServiceHook.emptyData, task: task, session: session)
        }
        orig.URLSession(session, task: task, didCompleteWithError: nil)
    }

    // MARK: - URLSessionDelegate
    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        // Capture authorization token from any request
        if let request = task.currentRequest,
           let headers = request.allHTTPHeaderFields,
           let auth = headers["Authorization"] ?? headers["authorization"],
           auth.hasPrefix("Bearer ") {
            spotifyAccessToken = String(auth.dropFirst(7))
        }

        guard let url = task.currentRequest?.url else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }

        // Handle blocked endpoints (session protection)
        if shouldBlock(url) {
            handleBlockedEndpoint(url, task: task, session: session)
            return
        }

        // Handle customize 304 that was already served in didReceiveResponse
        if SPTDataLoaderServiceHook.handledCustomizeTasks.remove(task.taskIdentifier) != nil {
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        // Avoid double processing for lyrics if we already served synthetic lyrics in didReceiveResponse
        if SPTDataLoaderServiceHook.handledLyricsTasks.remove(task.taskIdentifier) != nil {
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        guard error == nil, shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }

        guard let buffer = URLSessionHelper.shared.obtainData(for: url) else {
            // Customize 304 fallback: serve cached modified data when no buffer available
            if url.isCustomize, let cached = SPTDataLoaderServiceHook.cachedCustomizeData {
                respondWithCustomData(cached, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
            }
            return
        }

        do {
            if url.isLyrics {
                // Mark this task as handled to avoid reprocessing later
                SPTDataLoaderServiceHook.handledLyricsTasks.insert(task.taskIdentifier)
                let originalLyrics = try? Lyrics(serializedBytes: buffer)
                var customLyricsData: Data?
                let semaphore = DispatchSemaphore(value: 0)
                let workItem = DispatchWorkItem {
                    do {
                        customLyricsData = try getLyricsDataForCurrentTrack(
                            url.path,
                            originalLyrics: originalLyrics
                        )
                    } catch {
                        // Silently ignore error, fallback to original lyrics
                    }
                    semaphore.signal()
                }
                DispatchQueue.global(qos: .userInitiated).async(execute: workItem)

                let timeout = DispatchTime.now() + .seconds(5)
                let result = semaphore.wait(timeout: timeout)

                if result == .success, let data = customLyricsData {
                    workItem.cancel()
                    respondWithCustomData(data, task: task, session: session)
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                } else {
                    respondWithCustomData(buffer, task: task, session: session)
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                }
                return
            }

            if url.isPremiumPlanRow {
                let modifiedData = try getPremiumPlanRowData(
                    originalPremiumPlanRow: try PremiumPlanRow(serializedBytes: buffer)
                )
                respondWithCustomData(modifiedData, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }

            if url.isPremiumBadge {
                let badgeData = try getPremiumPlanBadge()
                respondWithCustomData(badgeData, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }

            if url.isCustomize {
                var customizeMessage = try CustomizeMessage(serializedBytes: buffer)
                modifyRemoteConfiguration(&customizeMessage.response)
                let modifiedData = try customizeMessage.serializedData()
                SPTDataLoaderServiceHook.cachedCustomizeData = modifiedData
                respondWithCustomData(modifiedData, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }

            if url.isPlanOverview {
                let overviewData = try getPlanOverviewData()
                respondWithCustomData(overviewData, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Handle customize 304 — prevent free-account data leaking from URLSession cache
        if let url = task.currentRequest?.url, url.isCustomize, response.statusCode == 304 {
            if let cached = SPTDataLoaderServiceHook.cachedCustomizeData {
                let fakeResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!
                orig.URLSession(session, dataTask: task, didReceiveResponse: fakeResponse, completionHandler: handler)
                respondWithCustomData(cached, task: task, session: session)
                SPTDataLoaderServiceHook.handledCustomizeTasks.insert(task.taskIdentifier)
                return
            }
        }

        guard
            let url = task.currentRequest?.url,
            url.isLyrics,
            response.statusCode != 200
        else {
            orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: handler)
            return
        }

        // For lyrics that would fail, we immediately return synthetic lyrics
        do {
            let data = try getLyricsDataForCurrentTrack(url.path)
            let okResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!

            // Mark that we already handled this task to avoid double processing
            SPTDataLoaderServiceHook.handledLyricsTasks.insert(task.taskIdentifier)
            orig.URLSession(session, dataTask: task, didReceiveResponse: okResponse, completionHandler: handler)
            respondWithCustomData(data, task: task, session: session)
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard let url = task.currentRequest?.url else {
            return
        }

        // Suppress data for blocked endpoints (prevent original data from reaching handler)
        if shouldBlock(url) {
            return
        }

        if shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: url)
            return
        }

        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
