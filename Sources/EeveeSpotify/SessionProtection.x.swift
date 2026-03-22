import Orion
import Foundation

// MARK: - Session Logout Protection
// Hooks all logout-related methods to prevent Spotify from logging out
// when it detects the account isn't actually premium.
// Also intercepts Ably WebSocket messages to block server-side revocation events.
// Additionally blocks network endpoints that trigger session invalidation.
// Extends OAuth token expiry to prevent internal reauth triggers.
// NEW: Adds manual refresh token handling using official Spotify SDK classes.

struct SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionImplementation — Core Session Hooks

class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"

    // orion:new
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

// MARK: - OauthAccessTokenBridge — Extend token expiry and store refresh token
// This private class inside Connectivity_SessionImpl controls the OAuth token's
// expiry time. By hooking expiresAt to return a far-future date, we prevent
// the internal timer from marking the token as expired.
// NEW: Store the refresh token for manual refresh.

class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"

    // NEW: Static storage for refresh token
    static var storedRefreshToken: String?

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

    // NEW: Hook setRefreshToken if exists (this method might not exist; we'll also try KVO)
    // We'll use a more generic approach: whenever the token is set, we capture it.
    // Since we can't guarantee the setter name, we'll instead hook the underlying property.
    // For simplicity, we'll use KVO on the target if possible, but here we'll implement a method
    // that might be called when the token is set. Alternatively, we can hook the setter via
    // class_getInstanceMethod and swizzle. Orion's method hooking can be used if the method exists.
    // The actual method name is likely "setRefreshToken:" or similar.
    func setRefreshToken(_ token: Any) {
        if let tokenString = token as? String {
            OauthAccessTokenBridgeHook.storedRefreshToken = tokenString
        }
        orig.setRefreshToken(token)
    }
}

// MARK: - SPTConfiguration Hook (official SDK) — to obtain clientID

class SPTConfigurationHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTConfiguration"

    static var clientID: String?
    static var redirectURL: URL?

    func initWithClientID(_ clientID: String, redirectURL: URL) -> NSObject? {
        let result = orig.initWithClientID(clientID, redirectURL: redirectURL)
        SPTConfigurationHook.clientID = clientID
        SPTConfigurationHook.redirectURL = redirectURL
        return result
    }
}

// MARK: - SPTSessionManager Hook (official SDK) — manual token refresh

class SPTSessionManagerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTSessionManager"

    func renewSession() {
        guard let refreshToken = OauthAccessTokenBridgeHook.storedRefreshToken else {
            orig.renewSession()
            return
        }

        performManualTokenRefresh(refreshToken: refreshToken) { [weak self] success, tokens in
            guard let self = self else { return }
            if success,
               let accessToken = tokens?["access_token"] as? String,
               let expiresIn = tokens?["expires_in"] as? Int {

                // Update current session via KVC (properties are public)
                if let session = self.target.value(forKey: "session") as? NSObject {
                    session.setValue(accessToken, forKey: "accessToken")
                    session.setValue(refreshToken, forKey: "refreshToken")
                    session.setValue(Date().addingTimeInterval(TimeInterval(expiresIn)), forKey: "expirationDate")
                }

                // Notify delegate if possible
                if let delegate = self.target.value(forKey: "delegate") as? NSObject,
                   delegate.responds(to: Selector(("sessionManager:didRenewSession:"))) {
                    _ = delegate.perform(Selector(("sessionManager:didRenewSession:")), with: self.target, with: self.target.value(forKey: "session"))
                }
                return
            }
            // Fallback to original (which will likely fail and cause logout, but we've done our best)
            self.orig.renewSession()
        }
    }

    private func performManualTokenRefresh(refreshToken: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        guard let clientID = SPTConfigurationHook.clientID else {
            completion(false, nil)
            return
        }

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)"
        request.httpBody = body.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["access_token"] != nil else {
                completion(false, nil)
                return
            }
            completion(true, json)
        }
        task.resume()
    }
}

// MARK: - SPTError Hook (official SDK) — block renew session errors

// Since we can't import the SDK, we'll define the error domain and codes manually.
let SPTLoginErrorDomain = "com.spotify.login"
let SPTRenewSessionFailedErrorCode = 2  // from SPTErrorCode enum

class SPTErrorHook: ClassHook<NSError> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTError"

    // Factory method: +errorWithCode:description:
    func errorWithCode(_ code: UInt, description: String) -> NSError? {
        if code == SPTRenewSessionFailedErrorCode {
            return nil  // suppress the error
        }
        return orig.errorWithCode(code, description: description)
    }

    // Factory method: +errorWithCode:underlyingError:
    func errorWithCode(_ code: UInt, underlyingError: NSError) -> NSError? {
        if code == SPTRenewSessionFailedErrorCode {
            return nil
        }
        return orig.errorWithCode(code, underlyingError: underlyingError)
    }
}

// MARK: - Ably WebSocket Transport Hooks
// Intercepts Ably real-time messages to block server-side logout/revocation events

// Blocked Ably protocol actions: 5=disconnect, 6=disconnected, 7=close, 8=closed, 9=error, 12=detach, 13=detached, 17=auth
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
// MODIFIED: Removed blocking of bootstrap/apresolve after 30s to allow proper session management.

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
                // REMOVED: bootstrap and apresolve blocking to avoid interfering with session refresh
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
