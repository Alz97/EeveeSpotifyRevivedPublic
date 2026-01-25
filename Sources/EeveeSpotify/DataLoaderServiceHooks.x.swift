import Foundation
import Orion

class SPTDataLoaderServiceHook: ClassHook<NSObject>, SpotifySessionDelegate {
    static let targetName = "SPTDataLoaderService"
    
    // orion:new
    func shouldModify(_ url: URL) -> Bool {
        let shouldPatchPremium = BasePremiumPatchingGroup.isActive
        let shouldReplaceLyrics = BaseLyricsGroup.isActive
        
        let isLyricsURL = url.isLyrics
        
        return (shouldReplaceLyrics && isLyricsURL)
            || (shouldPatchPremium && (url.isCustomize || url.isPremiumPlanRow || url.isPremiumBadge || url.isPlanOverview))
    }
    
    // orion:new
    func respondWithCustomData(_ data: Data, task: URLSessionDataTask, session: URLSession) {
        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
    
    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        guard let url = task.currentRequest?.url else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        guard error == nil, shouldModify(url) else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        guard let buffer = URLSessionHelper.shared.obtainData(for: url) else {
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
                        // Error handled below
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
                respondWithCustomData(try customizeMessage.serializedData(), task: task, session: session)
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

        if shouldModify(url) {
            URLSessionHelper.shared.setOrAppend(data, for: url)
            return
        }

        orig.URLSession(session, dataTask: task, didReceiveData: data)
    }
}
