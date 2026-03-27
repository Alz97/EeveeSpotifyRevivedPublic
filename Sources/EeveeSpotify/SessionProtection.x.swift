import Foundation
import Orion
import os

// MARK: - Sostituto di ManagedAtomic<Bool> (thread-safe, non mutante)
final class AtomicBool {
    private var value: Bool
    private var lock = os_unfair_lock_s()
    
    init(_ initialValue: Bool) {
        self.value = initialValue
    }
    
    func load(ordering: Any) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    
    func store(_ newValue: Bool, ordering: Any) {
        os_unfair_lock_lock(&lock)
        value = newValue
        os_unfair_lock_unlock(&lock)
    }
}

// MARK: - SessionLogoutHookGroup (definita solo se non esiste già)
class SessionLogoutHookGroup: HookGroup { }

// MARK: - SPTAuthSessionHook
class SPTAuthSessionHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthSessionImplementation"

    static let allowLogout = AtomicBool(false)   // ora è una classe, quindi let va bene

    func logout() {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.logout()
        }
    }

    func logoutWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.logoutWithReason(reason)
        }
    }

    func callSessionDidLogoutOnDelegateWithReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.callSessionDidLogoutOnDelegateWithReason(reason)
        }
    }

    func logWillLogoutEventWithLogoutReason(_ reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.logWillLogoutEventWithLogoutReason(reason)
        }
    }

    func destroy() {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
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

    private static var resetWorkItem: DispatchWorkItem?

    func automatedLogoutThenLogin() {
        // Block automated logout
    }

    func userInitiatedLogout() {
        if Thread.isMainThread {
            SessionServiceImplHook.resetWorkItem?.cancel()
            SPTAuthSessionHook.allowLogout.store(true, ordering: .relaxed)

            let workItem = DispatchWorkItem {
                SPTAuthSessionHook.allowLogout.store(false, ordering: .relaxed)
                SessionServiceImplHook.resetWorkItem = nil
            }
            SessionServiceImplHook.resetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)

            orig.userInitiatedLogout()
        }
    }

    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.sessionDidLogout(session, withReason: reason)
        }
    }
}

// MARK: - SPTAuthLegacyLoginControllerImplementation
class LegacyLoginControllerHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "SPTAuthLegacyLoginControllerImplementation"

    func sessionDidLogout(_ session: AnyObject, withReason reason: AnyObject) {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.sessionDidLogout(session, withReason: reason)
        }
    }

    func destroySession() {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.destroySession()
        }
    }

    func forgetStoredCredentials() {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.forgetStoredCredentials()
        }
    }

    func invalidate() {
        if SPTAuthSessionHook.allowLogout.load(ordering: .relaxed) {
            orig.invalidate()
        }
    }
}

// MARK: - OauthAccessTokenBridge — Extend token expiry
class OauthAccessTokenBridgeHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge"

    private var expiryTimer: DispatchSourceTimer?

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
        let queue = DispatchQueue.global(qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self = self else {
                timer.cancel()
                return
            }
            let cls: AnyClass = type(of: self.target)
            if let ivar = class_getInstanceVariable(cls, "expiresAt") {
                let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
                object_setIvar(self.target, ivar, farFuture)
            } else {
                timer.cancel()
            }
        }
        timer.resume()
        expiryTimer = timer
    }

    deinit {
        expiryTimer?.cancel()
    }
}

// MARK: - Ably WebSocket Transport Hooks

private let blockedAblyActions: Set<Int> = [5, 6, 7, 8, 9, 12, 13, 17]

private func extractAblyAction(from text: String) -> Int? {
    guard let data = text.data(using: .utf8) else { return nil }
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let action = json["action"] as? Int {
            return action
        }
    } catch {
        // ignore
    }
    return nil
}

class ARTWebSocketTransportHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "ARTWebSocketTransport"

    func webSocket(_ ws: AnyObject, didReceiveMessage message: AnyObject) {
        if let msgString = message as? String,
           let action = extractAblyAction(from: msgString),
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
           let action = extractAblyAction(from: text),
           blockedAblyActions.contains(action) {
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
        if let task = target as? URLSessionTask,
           let url = task.currentRequest?.url ?? task.originalRequest?.url,
           let host = url.host?.lowercased() {

            let elapsed = Date().timeIntervalSince(tweakInitTime)
            let path = url.path

            if host.contains("spotify") || host.contains("spclient") {
                if elapsed > 30 {
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
        }
        orig.resume()
    }
}
