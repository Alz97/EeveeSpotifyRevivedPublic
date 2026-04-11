import Orion
import EeveeSpotifyC
import UIKit

// Timestamp of tweak initialization — persists across Orion reinits within the same process
// using an environment variable. This prevents the 30s auth window from resetting
// when the C++ timer triggers a session reinit cycle.
let tweakInitTime: Date = {
    if let existing = getenv("EEVEE_BOOT_TIME"),
       let interval = Double(String(cString: existing)) {
        return Date(timeIntervalSince1970: interval)
    }
    let now = Date()
    setenv("EEVEE_BOOT_TIME", "\(now.timeIntervalSince1970)", 1)
    return now
}()

func exitApplication() {
    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        exit(EXIT_SUCCESS)
    }
}

// Timer per il loop continuo di protezione
var sessionProtectionTimer: Timer?

struct BasePremiumPatchingGroup: HookGroup { }
struct IOS14PremiumPatchingGroup: HookGroup { }
struct NonIOS14PremiumPatchingGroup: HookGroup { }
struct IOS14And15PremiumPatchingGroup: HookGroup { }
struct V91PremiumPatchingGroup: HookGroup { } // For Spotify 9.1.x versions
struct LatestPremiumPatchingGroup: HookGroup { }

func startSessionProtectionLoop() {
    // Attendi 30 secondi prima di avviare il loop per non interferire con l'avvio
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        // Timer che esegue ogni 60 secondi
        sessionProtectionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            // Forza allowLogout = false (se qualcosa l'ha reso true)
            SPTAuthSessionHook.allowLogout = false
            
            // Potresti anche forzare il rinnovo del token chiamando un metodo pubblico
            // Per esempio, se hai un riferimento alle istanze di OauthAccessTokenBridge,
            // potresti invocare extendExpiryIvar su ciascuna. Non avendo un modo diretto,
            // il timer interno di OauthAccessTokenBridgeHook dovrebbe già farlo.
            
            // Aggiungi eventuali altre azioni di manutenzione
        }
        // Assicurati che il timer sia eseguito sul main run loop
        RunLoop.main.add(sessionProtectionTimer!, forMode: .common)
    }
}

func activatePremiumPatchingGroup() {
    BasePremiumPatchingGroup().activate()
    
    if EeveeSpotify.hookTarget == .lastAvailableiOS14 {
        IOS14PremiumPatchingGroup().activate()
    }
    else if EeveeSpotify.hookTarget == .v91 {
        // 9.1.x versions: Use NonIOS14 hooks but skip offline content hooks
        NonIOS14PremiumPatchingGroup().activate()
        //V91PremiumPatchingGroup().activate()
        // Only activate if Spotify's UIView category method exists in this build —
        // the method was removed/renamed in 9.1.28 and hooking a missing method is a fatal crash.
        let trackRowsSel = Selector(("initWithViewURI:onDemandSet:onDemandTrialService:trackRowsEnabled:productState:"))
        if UIView.instancesRespond(to: trackRowsSel) {
            V91PremiumPatchingGroup().activate()
        }
    }
    else {
        NonIOS14PremiumPatchingGroup().activate()
        
        if EeveeSpotify.hookTarget == .lastAvailableiOS15 {
            IOS14And15PremiumPatchingGroup().activate()
        }
        else {
            LatestPremiumPatchingGroup().activate()
        }
    }
}

struct EeveeSpotify: Tweak {
    static let version = "6.7.0"
    static let buildNumber = "1"
    
    static var hookTarget: VersionHookTarget {
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        
        switch version {
        case "9.0.48":
            return .lastAvailableiOS15
        case "8.9.8":
            return .lastAvailableiOS14
        case _ where version.contains("9.1"):
            // 9.1.x versions don't have offline content helper classes
            return .v91
        default:
            return .latest
        }
    }
    
    init() {
        // Activate session logout protection first (all versions)
        SessionLogoutHookGroup().activate()

        // For 9.1.x, activate premium patching and lyrics
        if EeveeSpotify.hookTarget == .v91 {
            
            // Premium patching
            if UserDefaults.patchType.isPatching {
                BasePremiumPatchingGroup().activate()
            }
            
            let lyricsEnabled = UserDefaults.lyricsSource.isReplacingLyrics
            
            if lyricsEnabled {
                BaseLyricsGroup().activate()
                V91LyricsGroup().activate()
            }
            
            // Settings integration
            UniversalSettingsIntegrationGroup().activate()
            
            return
        }
        
        // For other versions, activate all features normally
        if UserDefaults.experimentsOptions.showInstagramDestination {
            InstgramDestinationGroup().activate()
        }
        
        if UserDefaults.darkPopUps {
            DarkPopUps().activate()
        }
        
        if UserDefaults.patchType.isPatching {
            activatePremiumPatchingGroup()
        }
        
        if UserDefaults.lyricsSource.isReplacingLyrics {
            BaseLyricsGroup().activate()
            LyricsErrorHandlingGroup().activate()
            
            if EeveeSpotify.hookTarget == .latest {
                ModernLyricsGroup().activate()
            }
            else {
                LegacyLyricsGroup().activate()
            }
        }
        
        // Always activate settings integration (except for 9.1.x which exits early above)
        UniversalSettingsIntegrationGroup().activate()
        SettingsIntegrationGroup().activate()

        // Avvia il loop di protezione dopo l'avvio dell'app
        startSessionProtectionLoop()
    }
}
