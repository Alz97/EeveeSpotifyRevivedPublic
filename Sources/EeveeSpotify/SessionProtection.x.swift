import Orion
import Foundation

// MARK: - Session Logout Protection
// Hooks all logout-related methods to prevent Spotify from logging out
// when it detects the account isn't actually premium.
// Also intercepts Ably WebSocket messages to block server-side revocation events.
// Additionally blocks network endpoints that trigger session invalidation.
// Extends OAuth token expiry to prevent internal reauth triggers.
// NEW: Manual refresh token handling via direct OAuth call.

struct SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionImplementation — Core Session Hooks

class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"

    static var allowLogout = false

    func logout() {
        if SPTAuthSessionHook.allowLogout {
            orig.logout()
        }
    }

    func logoutWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout {
            orig.logoutWithReason(reason)
        }
    }

    func callSessionDidLogoutOnDelegateWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout {
            orig.callSessionDidLogoutOnDelegateWithReason(reason)
        }
    }

    func logWillLogoutEventWithLogoutReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout {
            orig.logWillLogoutEventWithLogoutReason(reason)
        }
    }

    func destroy() {
        if SPTAuthSessionHook.allowLogout {
            orig.destroy()
        }
    }

    func productStateUpdated(_ state: AnyObject) {
        orig.productStateUpdated(state)
    }

    func tryReconnect(_ arg1: AnyObject, toAP arg2: AnyObject) {
        orig.tryReconnect(arg1, toAP: arg2)
    }
}

// MARK: - SessionServiceImpl (Connectivity_SessionImpl module)

class SessionServiceImplHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImpl18SessionServiceImpl"

    func automatedLogoutThenLogin() {
        // Block automated logout
    }

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
        if SPTAuthSessionHook.allowLogout {
            orig.sessionDidLogout(session, withReason: reason)
        }
    }
}

// MARK: - SPTAuthLegacyLoginControllerImplementation

class LegacyLoginControllerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthLegacyLoginControllerImplementation"

    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout {
            orig.sessionDidLogout(session, withReason: reason)
        }
    }

    func destroySession() {
        if SPTAuthSessionHook.allowLogout {
            orig.destroySession()
        }
    }

    func forgetStoredCredentials() {
        if SPTAuthSessionHook.allowLogout {
            orig.forgetStoredCredentials()
        }
    }

    func invalidate() {
        if SPTAuthSessionHook.allowLogout {
            orig.invalidate()
        }
    }
}

// MARK: - OauthAccessTokenBridge — Extend token expiry & manual refresh
// NEW: Added manual refresh logic to keep the token alive without relying on Spotify's internal refresh.

class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"

    // NEW: Store refresh token and client ID
    static var storedRefreshToken: String?
    // Known Spotify iOS client ID (fallback)
    static let clientID = "8f1c2b8f6f0a4e4b8c8e2b0f4f8c8e2b"

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

        // NEW: Capture refresh token when the object is created
        if let refreshToken = target.value(forKey: "refreshToken") as? String {
            OauthAccessTokenBridgeHook.storedRefreshToken = refreshToken
        }
        // NEW: Start proactive refresh timer
        startProactiveRefresh()
        return result
    }

    // orion:new
    func extendExpiryIvar() {
        let bridgeClass: AnyClass = type(of: target)
        if let ivar = class_getInstanceVariable(bridgeClass, "expiresAt") {
            let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
            object_setIvar(target, ivar, farFuture)
        }
    }

    // orion:new
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

    // NEW: Proactive refresh every 12 hours
    func startProactiveRefresh() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 12 * 60 * 60) // 12 hours
                guard let self = self else { break }
                guard let refreshToken = OauthAccessTokenBridgeHook.storedRefreshToken else { continue }
                self.performManualRefresh(refreshToken: refreshToken)
            }
        }
    }

    // NEW: Perform the actual token refresh using Spotify's OAuth endpoint
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
                return
            }
            DispatchQueue.main.async {
                // Update the target's access token and expiry via KVC
                self.target.setValue(accessToken, forKey: "accessToken")
                self.target.setValue(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "expiresAt")
                // If a new refresh token is returned, store it
                if let newRefresh = json["refresh_token"] as? String {
                    OauthAccessTokenBridgeHook.storedRefreshToken = newRefresh
                    self.target.setValue(newRefresh, forKey: "refreshToken")
                }
            }
        }
        task.resume()
    }
}

// MARK: - Error Logger Hooks (silence renew session errors)
let SPTLoginErrorDomain = "com.spotify.login"
let SPTRenewSessionFailedErrorCode: UInt64 = 2

class SPTLoginErrorLoggerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTLoginErrorLogger"

    func logErrorWithCode(_ code: UInt64, fieldidentifier: Any) {
        if code == SPTRenewSessionFailedErrorCode {
            return
        }
        orig.logErrorWithCode(code, fieldidentifier: fieldidentifier)
    }
}

class SPTE2ELoginErrorTrackerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTE2ELoginErrorTracker"

    class func postLoginErrorNotificationWithError(_ error: Any) {
        if let nsError = error as? NSError,
           nsError.domain == SPTLoginErrorDomain,
           nsError.code == Int(SPTRenewSessionFailedErrorCode) {
            return
        }
        orig.postLoginErrorNotificationWithError(error)
    }

    func receivedNotificationNamed(_ name: Any) {
        orig.receivedNotificationNamed(name)
    }
}

// MARK: - Ably WebSocket Transport Hooks
// Intercepts Ably real-time messages to block server-side logout/revocation events

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

// MARK: - Ably SRWebSocket Frame Hook

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

// MARK: - Global URLSessionTask hook to catch auth traffic bypassing SPTDataLoaderService
// Note: You may want to remove the blocks for "bootstrap" and "apresolve" to allow proper session refresh.
// They are currently still blocked. To unblock, comment out the respective lines.

class URLSessionTaskResumeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "NSURLSessionTask"

    func resume() {
        if let task = target as? URLSessionTask,
           let url = task.currentRequest?.url ?? task.originalRequest?.url,
           let host = url.host?.lowercased() {

            let elapsed = Date().timeIntervalSince(tweakInitTime)
            let path = url.path

            // Block outgoing DeleteToken/signup requests at network level
            // Only block after initial startup (30s) to allow fresh login/signup
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
                // COMMENT OUT THE FOLLOWING TWO LINES TO AVOID INTERFERING WITH SESSION REFRESH
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
