import Orion

class SpotifySessionDelegateBootstrapHook: ClassHook<NSObject>, SpotifySessionDelegate {
    static var targetName: String {
        switch EeveeSpotify.hookTarget {
        case .lastAvailableiOS14: return "SPTCoreURLSessionDataDelegate"
        default: return "SPTDataLoaderService"
        }
    }
    
    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveResponse response: HTTPURLResponse,
        completionHandler handler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        orig.URLSession(session, dataTask: task, didReceiveResponse: response, completionHandler: handler)
    }
    
    func URLSession(
        _ session: URLSession,
        dataTask task: URLSessionDataTask,
        didReceiveData data: Data
    ) {
        guard let url = task.currentRequest?.url, url.isBootstrap else {
            orig.URLSession(session, dataTask: task, didReceiveData: data)
            return
        }
        URLSessionHelper.shared.setOrAppend(data, for: url)
    }
    
    func URLSession(
        _ session: URLSession,
        task: URLSessionDataTask,
        didCompleteWithError error: Error?
    ) {
        guard
            let url = task.currentRequest?.url,
            url.isBootstrap,
            error == nil,
            let buffer = URLSessionHelper.shared.obtainData(for: url)
        else {
            orig.URLSession(session, task: task, didCompleteWithError: error)
            return
        }
        
        do {
            var bootstrapMessage = try BootstrapMessage(serializedBytes: buffer)
            
            if UserDefaults.patchType == .notSet {
                if bootstrapMessage.attributes["type"]?.stringValue == "premium" {
                    UserDefaults.patchType = .disabled
                    showHavePremiumPopUp()
                } else {
                    UserDefaults.patchType = .requests
                    DispatchQueue.main.async {
                        activatePremiumPatchingGroup()
                    }
                }
            }
            
            if UserDefaults.patchType == .requests {
                modifyRemoteConfiguration(&bootstrapMessage.ucsResponse)
                let modifiedData = try bootstrapMessage.serializedBytes()
                orig.URLSession(session, dataTask: task, didReceiveData: modifiedData)
            } else {
                orig.URLSession(session, dataTask: task, didReceiveData: buffer)
            }
            
            orig.URLSession(session, task: task, didCompleteWithError: nil)
        } catch {
            orig.URLSession(session, task: task, didCompleteWithError: error)
        }
    }
}

private func showHavePremiumPopUp() {
    PopUpHelper.showPopUp(
        delayed: true,
        message: "have_premium_popup".localized,
        buttonText: "OK".uiKitLocalized
    )
}
