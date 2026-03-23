import Orion
import Foundation

struct SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionImplementation

class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"
    static var allowLogout = false

    func logout() { if SPTAuthSessionHook.allowLogout { orig.logout() } }
    func logoutWithReason(_ reason: AnyObject) { if SPTAuthSessionHook.allowLogout { orig.logoutWithReason(reason) } }
    func callSessionDidLogoutOnDelegateWithReason(_ reason: AnyObject) { if SPTAuthSessionHook.allowLogout { orig.callSessionDidLogoutOnDelegateWithReason(reason) } }
    func logWillLogoutEventWithLogoutReason(_ reason: AnyObject) { if SPTAuthSessionHook.allowLogout { orig.logWillLogoutEventWithLogoutReason(reason) } }
    func destroy() { if SPTAuthSessionHook.allowLogout { orig.destroy() } }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { SPTAuthSessionHook.allowLogout = false }
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
    func destroySession() { if SPTAuthSessionHook.allowLogout { orig.destroySession() } }
    func forgetStoredCredentials() { if SPTAuthSessionHook.allowLogout { orig.forgetStoredCredentials() } }
    func invalidate() { if SPTAuthSessionHook.allowLogout { orig.invalidate() } }
}

// MARK: - OauthAccessTokenBridge (solo estensione expiry, niente refresh manuale)

class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"

    func expiresAt() -> Any { return Date(timeIntervalSinceNow: 365 * 24 * 60 * 60) }
    func setExpiresAt(_ date: Any) { orig.setExpiresAt(Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)) }

    func `init`() -> NSObject? {
        let result = orig.`init`()
        extendExpiryIvar()
        startExpiryExtender()
        return result
    }

    func extendExpiryIvar() {
        let cls = type(of: target)
        if let ivar = class_getInstanceVariable(cls, "expiresAt") {
            object_setIvar(target, ivar, Date(timeIntervalSinceNow: 365 * 24 * 60 * 60))
        }
    }

    func startExpiryExtender() {
        DispatchQueue.global(qos: .utility).async { [weak target] in
            while true {
                Thread.sleep(forTimeInterval: 60)
                guard let obj = target else { break }
                if let ivar = class_getInstanceVariable(type(of: obj), "expiresAt") {
                    object_setIvar(obj, ivar, Date(timeIntervalSinceNow: 365 * 24 * 60 * 60))
                }
            }
        }
    }
}

// MARK: - Ably WebSocket Hooks (invariati)

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
           blockedAblyActions.contains(action) { return }
        orig.webSocket(ws, didReceiveMessage: message)
    }
    func webSocket(_ ws: AnyObject, didFailWithError error: AnyObject) { }
}

class ARTSRWebSocketHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "ARTSRWebSocket"

    func _handleFrameWithData(_ data: NSData, opCode code: Int) {
        if code == 1,
           let text = String(data: data as Data, encoding: .utf8),
           let action = extractAblyAction(text),
           blockedAblyActions.contains(action) { return }
        orig._handleFrameWithData(data, opCode: code)
    }
}

// MARK: - Global URLSessionTaskHook (SENZA blocchi bootstrap/apresolve)

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
                if elapsed > 30 && path.contains("DeleteToken") { task.cancel(); return }
                if elapsed > 30 && path.contains("signup/public") { task.cancel(); return }
                if elapsed > 30 && path.contains("pses/screenconfig") { task.cancel(); return }
                // BOOTSTRAP E APRESOLVE NON SONO PIÙ BLOCCATI
                // if elapsed > 30 && path.contains("bootstrap/v1/bootstrap") { task.cancel(); return }
                // if elapsed > 30 && host.contains("apresolve") { task.cancel(); return }
            }
        }
        orig.resume()
    }
}
