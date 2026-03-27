import Orion
import Foundation
import os.atomics   // Per ManagedAtomic
import Darwin       // Per NSLog (opzionale)

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

    // Atomic flag per thread‑safe access
    static let allowLogout = ManagedAtomic<Bool>(false)

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

    // WorkItem per gestire il reset del flag di logout
    private static var resetWorkItem: DispatchWorkItem?

    func automatedLogoutThenLogin() {
        // Blocca completamente il logout automatico
    }

    func userInitiatedLogout() {
        if Thread.isMainThread {
            // Annulla eventuale reset precedente
            SessionServiceImplHook.resetWorkItem?.cancel()
            SPTAuthSessionHook.allowLogout.store(true, ordering: .relaxed)

            // Crea un nuovo work item per resettare il flag dopo 5 secondi
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
// This private class inside Connectivity_SessionImpl controls the OAuth token's
// expiry time. By hooking expiresAt to return a far-future date, we prevent
// the internal timer from marking the token as expired.

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
        guard let ivar = class_getInstanceVariable(bridgeClass, "expiresAt") else {
            NSLog("[SpotifyTweak] OauthAccessTokenBridge: ivar 'expiresAt' not found")
            return
        }
        let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
        object_setIvar(target, ivar, farFuture)
    }

    // orion:new
    func startExpiryExtender() {
        // Crea un timer su una coda seriale di utilità
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
                NSLog("[SpotifyTweak] OauthAccessTokenBridge: ivar 'expiresAt' lost, stopping timer")
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
// Intercepts Ably real-time messages to block server-side logout/revocation events

// Blocked Ably protocol actions: 5=disconnect, 6=disconnected, 7=close, 8=closed, 9=error, 12=detach, 13=detached, 17=auth
private let blockedAblyActions: Set<Int> = [5, 6, 7, 8, 9, 12, 13, 17]

// Funzione robusta per estrarre l'action da un messaggio JSON
private func extractAblyAction(from text: String) -> Int? {
    guard let data = text.data(using: .utf8) else { return nil }
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let action = json["action"] as? Int {
            return action
        }
    } catch {
        // Se il parsing fallisce, ignora il messaggio (meglio che crashare)
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

// MARK: - Ably SRWebSocket Frame Hook
class ARTSRWebSocketHook: ClassHook<NSObject> {
    typealias Group = SessionLogoutHookGroup
    static let targetName = "ARTSRWebSocket"

    func _handleFrameWithData(_ data: NSData, opCode code: Int) {
        if code == 1,  // Text frame
           let text = String(data: data as Data, encoding: .utf8),
           let action = extractAblyAction(from: text),
           blockedAblyActions.contains(action) {
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
        if let task = target as? URLSessionTask,
           let url = task.currentRequest?.url ?? task.originalRequest?.url,
           let host = url.host?.lowercased() {

            // tInitTime deve essere definita globalmente (ad esempio all'inizializzazione del tweak)
            let elapsed = Date().timeIntervalSince(tweakInitTime)
            let path = url.path

            // Blocca le richieste a endpoint sospetti solo dopo la fase di startup (30 secondi)
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
