import Orion
import SwiftUI
import UIKit
import Foundation

// MARK: - Gruppo principale per l'integrazione delle impostazioni
struct UniversalSettingsIntegrationGroup: HookGroup { }

// MARK: - Primary: ProfileSettingsSection hook (riga nel menu)
class UniversalProfileSettingsSectionHook: ClassHook<NSObject> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "ProfileSettingsSection"
    
    func numberOfRows() -> Int {
        return orig.numberOfRows() + 1
    }
    
    func didSelectRow(_ row: Int) {
        let originalRows = orig.numberOfRows()
        if row == originalRows {
            openEeveeSettings()
            return
        }
        orig.didSelectRow(row)
    }
    
    func cellForRow(_ row: Int) -> UITableViewCell {
        let originalRows = orig.numberOfRows()
        if row == originalRows {
            let cell = Dynamic.SPTSettingsTableViewCell
                .alloc(interface: SPTSettingsTableViewCell.self)
                .initWithStyle(3, reuseIdentifier: "EeveeSpotify")
            let tableViewCell = Dynamic.convert(cell, to: UITableViewCell.self)
            tableViewCell.accessoryView = type(
                of: Dynamic.SPTDisclosureAccessoryView
                    .alloc(interface: SPTDisclosureAccessoryView.self)
            ).disclosureAccessoryView()
            tableViewCell.textLabel?.text = "EeveeSpotify"
            return tableViewCell
        }
        return orig.cellForRow(row)
    }
    
    private func openEeveeSettings() {
        let root = WindowHelper.shared.findFirstViewController("RootSettingsViewController")
            ?? WindowHelper.shared.findFirstViewController("SettingsViewController")
            ?? WindowHelper.shared.findFirstViewController("ProfileViewController")
        guard let rootController = root, let nav = rootController.navigationController else { return }
        let vc = EeveeSettingsViewController(
            rootController.view.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: nav)),
            navigationTitle: "EeveeSpotify"
        )
        nav.pushViewController(vc, animated: true)
    }
}

// MARK: - Helper per iniettare il bottone a forma di ingranaggio
func injectEeveeButton(into target: UIViewController) {
    // Evita duplicati (tag 1337)
    if let items = target.navigationItem.rightBarButtonItems, items.contains(where: { $0.tag == 1337 }) {
        return
    }
    
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
    button.tintColor = .white
    
    let action = UIAction { [weak target] _ in
        guard let target = target, let nav = target.navigationController else { return }
        let vc = EeveeSettingsViewController(
            target.view.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: nav)),
            navigationTitle: "EeveeSpotify"
        )
        nav.pushViewController(vc, animated: true)
    }
    button.addAction(action, for: .touchUpInside)
    
    let item = UIBarButtonItem(customView: button)
    item.tag = 1337
    item.customView?.widthAnchor.constraint(equalToConstant: 22).isActive = true
    item.customView?.heightAnchor.constraint(equalToConstant: 22).isActive = true
    
    var items = target.navigationItem.rightBarButtonItems ?? []
    items.insert(item, at: 0)
    target.navigationItem.rightBarButtonItems = items
}

// MARK: - Fallback 1: Hook per SettingsViewController
class SettingsViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "SettingsViewController"
    
    func viewDidLoad() {
        orig.viewDidLoad()
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
}

// MARK: - Fallback 2: Hook per RootSettingsViewController
class RootSettingsViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "RootSettingsViewController"
    
    func viewDidLoad() {
        orig.viewDidLoad()
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
}

// MARK: - Fallback 3: Hook per ProfileViewController (spesso il root delle impostazioni)
class ProfileViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "ProfileViewController"
    
    func viewDidLoad() {
        orig.viewDidLoad()
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
}

// MARK: - Fallback 4: Hook per UINavigationController per intercettare la push di viewController con titolo "Settings"
class SettingsNavigationStackHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup
    
    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        
        let targetVC = viewController
        let checkBlock = {
            let className = String(describing: type(of: targetVC))
            
            // Titoli delle impostazioni in moltissime lingue
            let settingsTitles: Set<String> = [
                "Settings", "Preferences", "Einstellungen", "Präferenzen",
                "Paramètres", "Préférences", "Configuración", "Ajustes",
                "Impostazioni", "Preferenze", "Definições", "Configurações",
                "Instellingen", "Voorkeuren", "Ayarlar", "Tercihler",
                "Ustawienia", "Preferencje", "Настройки", "Параметры",
                "Налаштування", "Параметри", "Nastavení", "Předvolby",
                "Inställningar", "Innstillinger", "Indstillinger", "Asetukset",
                "Beállítások", "Setări", "Preferințe", "Nastavenia",
                "Postavke", "Podešavanja", "Nastavitve", "Настройки",
                "Ρυθμίσεις", "Προτιμήσεις", "הגדרות", "העדפות",
                "الإعدادات", "التفضيلات", "تنظیمات", "ترجیحات",
                "設定", "環境設定", "설정", "환경설정", "设置", "偏好设置",
                "設定", "偏好設定", "การตั้งค่า", "Cài đặt", "Tùy chọn",
                "Pengaturan", "Setelan", "Preferensi", "Tetapan", "Keutamaan",
                "Mga Setting", "Mga Kagustuhan", "सेटिंग", "प्राथमिकताएं",
                "সেটিংস", "அமைப்புகள்", "Configuració", "Preferències",
                "Ezarpenak", "Configuración", "Preferencias"
            ]
            
            if let title = targetVC.title, settingsTitles.contains(title) {
                injectEeveeButton(into: targetVC)
                return
            }
            
            if className.contains("Settings") && !className.contains("Eevee") {
                injectEeveeButton(into: targetVC)
                return
            }
        }
        
        // Tentativi multipli
        checkBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: checkBlock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: checkBlock)
    }
}

// MARK: - Fallback 5: Hook per SPTNavigationController (usato da Spotify)
class SPTNavigationControllerHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "SPTNavigationController"
    
    func viewDidLoad() {
        orig.viewDidLoad()
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        // Prova a iniettare nel topViewController se è una schermata di impostazioni
        if let topVC = target.topViewController, isSettingsViewController(topVC) {
            injectEeveeButton(into: topVC)
        }
    }
    
    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        if isSettingsViewController(viewController) {
            injectEeveeButton(into: viewController)
        }
    }
    
    private func isSettingsViewController(_ vc: UIViewController) -> Bool {
        let className = String(describing: type(of: vc))
        return className.contains("Settings") || className.contains("Profile")
    }
}

// MARK: - Hook per UINavigationItem per prevenire la rimozione del bottone
class UINavigationItemHook: ClassHook<UINavigationItem> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "UINavigationItem"
    
    func setRightBarButtonItems(_ items: [UIBarButtonItem]?, animated: Bool) {
        // Se stanno per sovrascrivere i nostri items, reinseriamo il nostro
        if let currentItems = target.rightBarButtonItems,
           currentItems.contains(where: { $0.tag == 1337 }),
           let newItems = items,
           !newItems.contains(where: { $0.tag == 1337 }) {
            var modifiedItems = newItems
            let ourItem = currentItems.first(where: { $0.tag == 1337 })!
            modifiedItems.insert(ourItem, at: 0)
            orig.setRightBarButtonItems(modifiedItems, animated: animated)
        } else {
            orig.setRightBarButtonItems(items, animated: animated)
        }
    }
}

// MARK: - Attivazione all'interno del tweak principale
struct EeveeSpotify: Tweak {
    static let version = "6.6.0"
    
    init() {
        // Attiva sempre il gruppo di integrazione (che contiene tutti gli hook)
        UniversalSettingsIntegrationGroup().activate()
        
        // Se vuoi attivare anche altri gruppi (es. premium, lyrics), fallo qui
        // ...
    }
}
