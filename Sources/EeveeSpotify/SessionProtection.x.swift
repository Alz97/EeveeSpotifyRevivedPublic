import Orion
import Foundation

// MARK: - Session Logout Protection
struct SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionImplementation — Core Session Hooks
class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"
    static var allowLogout = false

    func logout() {
        if SPTAuthSessionHook.allowLogout { orig.logout() }
    }
    func logoutWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout { orig.logoutWithReason(reason) }
    }
    func callSessionDidLogoutOnDelegateWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout { orig.callSessionDidLogoutOnDelegateWithReason(reason) }
    }
    func logWillLogoutEventWithLogoutReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout { orig.logWillLogoutEventWithLogoutReason(reason) }
    }
    func destroy() {
        if SPTAuthSessionHook.allowLogout { orig.destroy() }
    }
    func productStateUpdated(_ state: AnyObject) { orig.productStateUpdated(state) }
    func tryReconnect(_ arg1: AnyObject, toAP arg2: AnyObject) { orig.tryReconnect(arg1, toAP: arg2) }
}

// MARK: - SessionServiceImpl
class SessionServiceImplHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImpl18SessionServiceImpl"

    func automatedLogoutThenLogin() { }
    func userInitiatedLogout() {
        if Thread.isMainThread {
            SPTAuthSessionHook.allowLogout = true
            orig.userInitiatedLogout()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                SPTAuthSessionHook.allowLogout = false
            }
        }
    }
    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout { orig.sessionDidLogout(session, withReason: reason) }
    }
}

// MARK: - SPTAuthLegacyLoginControllerImplementation
class LegacyLoginControllerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthLegacyLoginControllerImplementation"

    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout { orig.sessionDidLogout(session, withReason: reason) }
    }
    func destroySession() {
        if SPTAuthSessionHook.allowLogout { orig.destroySession() }
    }
    func forgetStoredCredentials() {
        if SPTAuthSessionHook.allowLogout { orig.forgetStoredCredentials() }
    }
    func invalidate() {
        if SPTAuthSessionHook.allowLogout { orig.invalidate() }
    }
}

// MARK: - OauthAccessTokenBridge — Extend token expiry + Safe Manual Refresh
class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"

    static var storedRefreshToken: String?
    static let clientID = "8f1c2b8f6f0a4e4b8c8e2b0f4f8c8e2b" // Spotify iOS client ID

    // Timer for proactive refresh
    private var refreshTimer: DispatchSourceTimer?

    func expiresAt() -> Any {
        return Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
    }

    func setExpiresAt(_ date: Any) {
        let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
        orig.setExpiresAt(farFuture)
    }

    func `init`() -> NSObject? {
        let result = orig.`init`()
        extendExpiryIvar()
        startExpiryExtender()

        // Capture refresh token safely
        if let refreshToken = safeRefreshToken() {
            OauthAccessTokenBridgeHook.storedRefreshToken = refreshToken
            startProactiveRefresh()
        }
        return result
    }

    private func safeRefreshToken() -> String? {
        // Use try-catch to prevent crash if key doesn't exist
        do {
            if let token = target.value(forKey: "refreshToken") as? String {
                return token
            }
        } catch {
            // Silently fail – token not available yet
        }
        return nil
    }

    func extendExpiryIvar() {
        let bridgeClass: AnyClass = type(of: target)
        if let ivar = class_getInstanceVariable(bridgeClass, "expiresAt") {
            let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
            object_setIvar(target, ivar, farFuture)
        }
    }

    func startExpiryExtender() {
        DispatchQueue.global(qos: .utility).async { [weak target] in
            while true {
                Thread.sleep(forTimeInterval: 60)
                guard let obj = target else { break }
                let cls: AnyClass = type(of: obj)
                if let ivar = class_getInstanceVariable(cls, "expiresAt") {
                    let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
                    object_setIvar(obj, ivar, farFuture)
                }
            }
        }
    }

    // Start a timer that triggers every 12 hours to refresh the token
    func startProactiveRefresh() {
        // Cancel any existing timer
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + 12 * 60 * 60, repeating: 12 * 60 * 60)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard let refreshToken = OauthAccessTokenBridgeHook.storedRefreshToken else { return }
            self.performManualRefresh(refreshToken: refreshToken)
        }
        timer.resume()
        refreshTimer = timer
    }

    func performManualRefresh(refreshToken: String) {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(OauthAccessTokenBridgeHook.clientID)"
        request.httpBody = body.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int else {
                // Refresh failed – do nothing, maybe retry later
                return
            }
            DispatchQueue.main.async {
                // Update token only if the object still exists
                if let target = self.target {
                    target.setValue(accessToken, forKey: "accessToken")
                    target.setValue(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "expiresAt")
                    if let newRefresh = json["refresh_token"] as? String {
                        OauthAccessTokenBridgeHook.storedRefreshToken = newRefresh
                        target.setValue(newRefresh, forKey: "refreshToken")
                    }
                }
            }
        }
        task.resume()
    }
}

// MARK: - Ably WebSocket Transport Hooks
private let blockedAblyActions: Set<Int> = [5, 6, 7, 8, 9, 12, 13, 17]

private func extractAblyAction(_ text: String) -> Int? {
    guard let range = text.range(of: "\"action\":") else { return nil }
    let afterAction = text[range.upperBound...]
    let digits = afterAction.prefix(while: { $0.isNumber })
    return Int(digits)
}

class ARTWebSocketTransportHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "ARTWebSocketTransport"

    func webSocket(_ ws: AnyObject, didReceiveMessage message: AnyObject) {
        if let msgString = message as? String,
           let action = extractAblyAction(msgString),
           blockedAblyActions.contains(action) {
            return
        }
        orig.webSocket(ws, didReceiveMessage: message)
    }

    func webSocket(_ ws: AnyObject, didFailWithError error: AnyObject) {
        // Silently ignore errors
    }
}

class ARTSRWebSocketHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "ARTSRWebSocket"

    func _handleFrameWithData(_ data: NSData, opCode code: Int) {
        if code == 1,
           let text = String(data: data as Data, encoding: .utf8),
           let action = extractAblyAction(text),
           blockedAblyActions.contains(action) {
            return
        }
        orig._handleFrameWithData(data, opCode: code)
    }
}

// MARK: - Global URLSessionTask hook — BLOCKS REMOVED FOR BOOTSTRAP/APRESOLVE
class URLSessionTaskResumeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "NSURLSessionTask"

    func resume() {
        if let task = target as? URLSessionTask,
           let url = task.currentRequest?.url ?? task.originalRequest?.url,
           let host = url.host?.lowercased() {

            let elapsed = Date().timeIntervalSince(tweakInitTime)
            let path = url.path

            if host.contains("spotify") || host.contains("spclient") {
                if elapsed > 30 && path.contains("DeleteToken") {
                    task.cancel()
                    return
                }
                if elapsed > 30 && path.contains("signup/public") {
                    task.cancel()
                    return
                }
                if elapsed > 30 && path.contains("pses/screenconfig") {
                    task.cancel()
                    return
                }
                // Bootstrap and apresolve are NOT blocked
                // if elapsed > 30 && path.contains("bootstrap/v1/bootstrap") {
                //     task.cancel()
                //     return
                // }
                // if elapsed > 30 && host.contains("apresolve") {
                //     task.cancel()
                //     return
                // }
            }
        }
        orig.resume()
    }
}
