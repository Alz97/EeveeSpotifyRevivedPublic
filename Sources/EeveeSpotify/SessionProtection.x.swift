import Orion
import Foundation
import os
import ObjectiveC.runtime

// MARK: - Session Logout Protection

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

// MARK: - OauthAccessTokenBridge — Extend token expiry

class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"
    
    func expiresAt() -> Any {
        return Date.distantFuture
    }

    func setExpiresAt(_ date: Any) {
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

private let blockedAblyActions: Set<Int> = [5, 6, 7, 8, 9, 12, 13, 17]

private func extractAblyAction(_ text: String) -> Int? {
    guard let range = text.range(of: "\"action\":") else { return nil }
    let afterAction = text[range.upperBound...]
    let digits = afterAction.prefix(while: { $0.isNumber })
    return Int(digits)
}

private func shouldBlockAblyMessage(_ text: String) -> Bool {
    if let action = extractAblyAction(text), blockedAblyActions.contains(action) {
        return true
    }
    
    if let action = extractAblyAction(text), action == 15 {
        if text.contains("product-state-update") ||
           text.contains("product_state_update") ||
           text.contains("productStateUpdate") {
            return true
        }
    }
    
    let lowercased = text.lowercased()
    return lowercased.contains("logout") || lowercased.contains("revoke") || lowercased.contains("disconnect")
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
        // Ignore
    }
}

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

// MARK: - Global URLSessionTask hook

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

        let elapsed = Date().timeIntervalSince(tweakInitTime)
        let path = url.path
        let absolute = url.absoluteString

        if elapsed > 30 {
            let logoutKeywords = ["logout", "revoke", "delete", "signout", "terminate", "invalidate", "destroy"]
            for keyword in logoutKeywords {
                if path.contains(keyword) || absolute.contains(keyword) {
                    task.cancel()
                    return
                }
            }
        }

        if elapsed > 30 {
            if host.contains("spotify") || host.contains("spclient") || host.contains("ably") {
                // Nota: bootstrap/v1/bootstrap NON viene bloccato per permettere il login iniziale
                if path.contains("DeleteToken") ||
                   path.contains("signup/public") ||
                   path.contains("pses/screenconfig") ||
                   path.contains("/signup/public/v1/account") ||
                   path.contains("account?") ||
                   path.contains("sdk-exp") ||
                   path.contains("reachability/check") ||
                   path.contains("customize") ||
                   host.contains("apresolve") {
                    task.cancel()
                    return
                }
            }
        }

        orig.resume()
    }
}
