import Foundation
import Orion
import os

// MARK: - Token storage (thread-safe) - mantenuto dal primo esempio
private struct TokenStorage {
    private static var _value: String?
    private static var lock = os_unfair_lock_s()
    
    static var value: String? {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return _value
        }
        set {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            _value = newValue
        }
    }
}

public var spotifyAccessToken: String? {
    get { TokenStorage.value }
    set { TokenStorage.value = newValue }
}

// Hook principale - stile del secondo esempio (modulare con SpotifyResponsePatcher)
class SPTDataLoaderServiceHook: ClassHook<NSObject>, SpotifySessionDelegate {
    typealias Group = PremiumBootstrapGroup
    static let targetName = "SPTDataLoaderService"

    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        // Cattura il token da qualsiasi richiesta (come nel primo esempio)
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

        // Blocca endpoint come nel secondo esempio, usando il patcher
        if SpotifyResponsePatcher.shouldBlock(url) {
            orig.URLSession(session, dataTask: task, didReceiveData: SpotifyResponsePatcher.blockedResponseData(for: url))
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        // Gestione 304 già servita
        if SpotifyResponsePatcher.handledCustomizeTasks.remove(task.taskIdentifier) != nil {
            orig.URLSession(session, task: task, didCompleteWithError: nil)
            return
        }

        guard error == nil, SpotifyResponsePatcher.shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }

        guard let buffer = URLSessionHelper.shared.obtainData(for: url) else {
            // Fallback per customize 304 con cache
            if url.isCustomize, let cached = SpotifyResponsePatcher.cachedCustomizeData {
                orig.URLSession(session, dataTask: task, didReceiveData: cached)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
            }
            return
        }

        do {
            // Lyrics con timeout asincrono (stile secondo esempio)
            if url.isLyrics {
                let originalLyrics = try? Lyrics(serializedBytes: buffer)
                let semaphore = DispatchSemaphore(value: 0)
                var customLyricsData: Data?

                DispatchQueue.global(qos: .userInitiated).async {
                    customLyricsData = try? getLyricsDataForCurrentTrack(url.path, originalLyrics: originalLyrics)
                    semaphore.signal()
                }

                _ = semaphore.wait(timeout: .now() + .milliseconds(5000))
                orig.URLSession(session, dataTask: task, didReceiveData: customLyricsData ?? buffer)
                orig.URLSession(session, task: task, didCompleteWithError: nil)
                return
            }

            if let result = try SpotifyResponsePatcher.patch(url: url, buffer: buffer) {
                writeDebugLog("[DL] Patched \(result.tag.rawValue)")
                orig.URLSession(session, dataTask: task, didReceiveData: result.data)
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
        // Gestione customize 304 (stile secondo esempio)
        if let url = task.currentRequest?.url, url.isCustomize, response.statusCode == 304,
           let cached = SpotifyResponsePatcher.cachedCustomizeData {
            let synthetic = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!
            orig.URLSession(session, dataTask: task, didReceiveResponse: synthetic, completionHandler: handler)
            orig.URLSession(session, dataTask: task, didReceiveData: cached)
            SpotifyResponsePatcher.handledCustomizeTasks.insert(task.taskIdentifier)
            return
        }

        // Lyrics con risposta non 200 – sostituisci con fetch custom
        guard let url = task.currentRequest?.url, url.isLyrics, response.statusCode != 200 else {
            orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: handler)
            return
        }

        do {
            let data = try getLyricsDataForCurrentTrack(url.path)
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2.0", headerFields: [:])!
            orig.URLSession(session, dataTask: task, didReceiveResponse: ok, completionHandler: handler)
            orig.URLSession(session, dataTask: task, didReceiveData: data)
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }

    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard let url = task.currentRequest?.url else { return }

        // Sopprime i dati originali per endpoint che verranno rimpiazzati
        if SpotifyResponsePatcher.shouldBlock(url) { return }
        if SpotifyResponsePatcher.shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: url)
            return
        }
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
