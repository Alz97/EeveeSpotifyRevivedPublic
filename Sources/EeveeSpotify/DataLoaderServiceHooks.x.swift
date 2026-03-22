import Foundation
import Orion

// Global variable for access token (original)
public var spotifyAccessToken: String?

// MARK: - SPTDataLoaderService Hook (Hi-Fi removed)
class SPTDataLoaderServiceHook: ClassHook<NSObject>, SpotifySessionDelegate {
    static let targetName = "SPTDataLoaderService"

    static var cachedCustomizeData: Data?
    static var handledCustomizeTasks = Set<Int>()

    func shouldBlock(_ url: URL) -> Bool {
        return url.isDeleteToken || url.isAccountValidate || url.isOndemandSelector
            || url.isTrialsFacade || url.isPremiumMarketing || url.isPendragonFetchMessageList
            || url.isSessionInvalidation || url.isPushkaTokens
    }

    func shouldModify(_ url: URL) -> Bool {
        let shouldPatchPremium = BasePremiumPatchingGroup.isActive
        let shouldReplaceLyrics = BaseLyricsGroup.isActive
        
        return (shouldReplaceLyrics && url.isLyrics)
            || (shouldPatchPremium && (url.isCustomize || url.isPremiumPlanRow || url.isPremiumBadge || url.isPlanOverview || url.isDeviceCapabilities))
    }
    
    func respondWithCustomData(_ data: Data, task: URLSessionDataTask, session: URLSession) {
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }

    func handleBlockedEndpoint(_ url: URL, task: URLSessionDataTask, session: URLSession) {
        if url.isDeleteToken {
            respondWithCustomData(Data(), task: task, session: session)
        } else if url.isAccountValidate {
            let response = "{\"status\":1,\"country\":\"IT\",\"is_country_launched\":true}".data(using: .utf8)!
            respondWithCustomData(response, task: task, session: session)
        } else if url.isOndemandSelector {
            respondWithCustomData(Data(), task: task, session: session)
        } else if url.isTrialsFacade {
            let response = "{\"result\":\"NOT_ELIGIBLE\"}".data(using: .utf8)!
            respondWithCustomData(response, task: task, session: session)
        } else if url.isPremiumMarketing {
            respondWithCustomData("{}".data(using: .utf8)!, task: task, session: session)
        } else if url.isPendragonFetchMessageList {
            respondWithCustomData(Data(), task: task, session: session)
        } else if url.isPushkaTokens {
            respondWithCustomData(Data(), task: task, session: session)
        } else if url.isSessionInvalidation {
            respondWithCustomData(Data(), task: task, session: session)
        }
        orig.URLSession(session, task: task, didCompleteWithError: nil)
    }

    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
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

        if shouldBlock(url) {
            handleBlockedEndpoint(url, task: task, session: session)
            return
        }

        if SPTDataLoaderServiceHook.handledCustomizeTasks.remove(task.taskIdentifier) != nil {
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        guard error == nil, shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        guard let buffer = URLSessionHelper.shared.obtainData(for: url) else {
            if url.isCustomize, let cached = SPTDataLoaderServiceHook.cachedCustomizeData {
                respondWithCustomData(cached, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
            }
            return
        }
        
        do {
            if url.isLyrics {
                let originalLyrics = try? Lyrics(serializedBytes: buffer)
                let semaphore = DispatchSemaphore(value: 0)
                var customLyricsData: Data?
                
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        customLyricsData = try getLyricsDataForCurrentTrack(
                            url.path,
                            originalLyrics: originalLyrics
                        )
                    } catch {
                    }
                    semaphore.signal()
                }
                
                let timeout = DispatchTime.now() + .milliseconds(5000)
                let result = semaphore.wait(timeout: timeout)
                
                if result == .success, let data = customLyricsData {
                    respondWithCustomData(data, task: task, session: session)
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                } else {
                    respondWithCustomData(buffer, task: task, session: session)
                    orig.URLSession(session, task: task, didCompleteWithError: nil)
                }
                return
            }
            
            if url.isPremiumPlanRow {
                respondWithCustomData(
                    try getPremiumPlanRowData(
                        originalPremiumPlanRow: try PremiumPlanRow(serializedBytes: buffer)
                    ),
                    task: task,
                    session: session
                )
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            
            if url.isPremiumBadge {
                respondWithCustomData(try getPremiumPlanBadge(), task: task, session: session)
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

            if url.isDeviceCapabilities {
                // Pass through original data (Hi-Fi removed)
                respondWithCustomData(buffer, task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
            
            if url.isPlanOverview {
                respondWithCustomData(try getPlanOverviewData(), task: task, session: session)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }
        }
        catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
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

        do {
            let data = try getLyricsDataForCurrentTrack(url.path)
            let okResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!
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
