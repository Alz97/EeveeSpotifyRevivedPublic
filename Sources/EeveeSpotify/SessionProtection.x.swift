import Orion
import Foundation
import os

// MARK: - Session Logout Protection
// Hooks all logout-related methods to prevent Spotify from logging out
// when it detects the account isn't actually premium.
// Also intercepts Ably WebSocket messages to block server-side revocation events.
// Additionally blocks network endpoints that trigger session invalidation.
// Extends OAuth token expiry to prevent internal reauth triggers.

struct SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionImplementation — Core Session Hooks

class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"

    // Thread-safe storage for allowLogout
    private static var _allowLogout = false
    private static var allowLogoutLock = os_unfair_lock_s()
    
    static var allowLogout: Bool {
        get {
            os_unfair_lock_lock(&allowLogoutLock)
            defer { os_unfair_lock_unlock(&allowLogoutLock) }
            return _allowLogout
        }
        set {
            os_unfair_lock_lock(&allowLogoutLock)
            defer { os_unfair_lock_unlock(&allowLogoutLock) }
            _allowLogout = newValue
        }
    }

    // Blocca sempre il logout – rimuovo la condizione, ma mantengo il flag per compatibilità
    func logout() {
        // Il flag non viene mai impostato a true, quindi orig.logout() non viene mai chiamato
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
        // Block automated logout – non fa nulla
    }

    func userInitiatedLogout() {
        // Blocca il logout anche se chiamato dall'utente
        // Non imposto allowLogout a true, né chiamo orig.userInitiatedLogout()
        return
    }

    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        // Blocca il callback di logout
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

// MARK: - OauthAccessTokenBridge — Extend token expiry
// This private class inside Connectivity_SessionImpl controls the OAuth token's
// expiry time. By hooking expiresAt to return a far-future date, we prevent
// the internal timer from marking the token as expired.

class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"
    
    func expiresAt() -> Any {
        // Usa una data molto lontana
        return Date.distantFuture
    }

    func setExpiresAt(_ date: Any) {
        // Ignora qualsiasi impostazione di scadenza reale
        orig.setExpiresAt(Date.distantFuture)
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
            object_setIvar(target, ivar, Date.distantFuture)
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
                    object_setIvar(obj, ivar, Date.distantFuture)
                }
            }
        }
    }
}

// MARK: - Ably WebSocket Transport Hooks
// Intercepts Ably real-time messages to block server-side logout/revocation events

// Blocca azioni Ably sospette e qualsiasi messaggio che contenga "logout" o "revoke"
private let blockedAblyActions: Set<Int> = [5, 6, 7, 8, 9, 12, 13, 17]
private func shouldBlockAblyMessage(_ text: String) -> Bool {
    // Controlla azione numerica
    if let action = extractAblyAction(text), blockedAblyActions.contains(action) {
        return true
    }
    // Controlla parole chiave
    let lowercased = text.lowercased()
    return lowercased.contains("logout") || lowercased.contains("revoke") || lowercased.contains("disconnect")
}

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
        if let msgString = message as? String, shouldBlockAblyMessage(msgString) {
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
           shouldBlockAblyMessage(text) {
            return
        }
        orig._handleFrameWithData(data, opCode: code)
    }
}

// MARK: - Global URLSessionTask hook to catch auth traffic bypassing SPTDataLoaderService

class URLSessionTaskResumeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "NSURLSessionTask"

    func resume() {
        guard let task = target as? URLSessionTask,
              let url = task.currentRequest?.url ?? task.originalRequest?.url,
              let host = url.host else {
            orig.resume()
            return
        }

        let path = url.path
        let absolute = url.absoluteString

        // Blocca qualsiasi richiesta che contenga parole chiave di logout (solo dopo 30s)
        if elapsed > 30 {
            let logoutKeywords = ["logout", "revoke", "delete", "signout", "terminate", "invalidate", "destroy"]
            for keyword in logoutKeywords {
                if path.contains(keyword) || absolute.contains(keyword) {
                    task.cancel()
                    return
                }
            }
        }

        // Blocca endpoint critici noti (solo dopo 30s)
        if elapsed > 30 {
            if host.contains("spotify") || host.contains("spclient") || host.contains("ably") {
                if path.contains("DeleteToken") ||
                   path.contains("signup/public") ||
                   path.contains("pses/screenconfig") ||
                   path.contains("bootstrap/v1/bootstrap") ||
                   host.contains("apresolve") {
                    task.cancel()
                    return
                }
            }
        }

        orig.resume()
    }
}
