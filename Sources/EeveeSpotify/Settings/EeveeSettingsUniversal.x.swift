import Orion
import SwiftUI
import UIKit
import Foundation

// Universal settings integration group
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

// MARK: - Helper per iniettare il bottone
func injectEeveeButton(into target: UIViewController) {
    if let items = target.navigationItem.rightBarButtonItems, items.contains(where: { $0.tag == 1337 }) {
        return
    }
    
    let button = UIButton(type: .system)
    let image = UIImage(systemName: "gearshape.fill")?.withRenderingMode(.alwaysOriginal) // mantiene il colore
    button.setImage(image, for: .normal)
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

// MARK: - Fallback hooks (solo se ProfileSettingsSection non esiste)
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
    
    // AGGIUNTA: inietta anche dopo che la vista è apparsa (UI pronta)
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        injectEeveeButton(into: target)
    }
}

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

// AGGIUNTA: Hook per ProfileViewController (spesso il root delle impostazioni)
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

class SettingsNavigationStackHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup

    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        
        let targetVC = viewController
        
        let checkBlock = {
            let className = String(describing: type(of: targetVC))
            
            // (stessa lista titoli dell'originale, mantenuta)
            let settingsTitles: Set<String> = [
                // English
                "Settings", "Preferences",
                // German
                "Einstellungen", "Präferenzen",
                // French
                "Paramètres", "Préférences",
                // Spanish
                "Configuración", "Ajustes", "Preferencias",
                // Italian
                "Impostazioni", "Preferenze",
                // Portuguese
                "Definições", "Configurações", "Preferências",
                // Dutch
                "Instellingen", "Voorkeuren",
                // Turkish
                "Ayarlar", "Tercihler",
                // Polish
                "Ustawienia", "Preferencje",
                // Russian
                "Настройки", "Параметры",
                // Ukrainian
                "Налаштування", "Параметри",
                // Czech
                "Nastavení", "Předvolby",
                // Swedish
                "Inställningar",
                // Norwegian
                "Innstillinger",
                // Danish
                "Indstillinger",
                // Finnish
                "Asetukset",
                // Hungarian
                "Beállítások",
                // Romanian
                "Setări", "Preferințe",
                // Slovak
                "Nastavenia",
                // Croatian/Bosnian/Serbian
                "Postavke", "Podešavanja",
                // Slovenian
                "Nastavitve",
                // Bulgarian
                "Настройки",
                // Greek
                "Ρυθμίσεις", "Προτιμήσεις",
                // Hebrew
                "הגדרות", "העדפות",
                // Arabic
                "الإعدادات", "التفضيلات",
                // Persian
                "تنظیمات", "ترجیحات",
                // Japanese
                "設定", "環境設定",
                // Korean
                "설정", "환경설정",
                // Chinese (Simplified)
                "设置", "偏好设置",
                // Chinese (Traditional)
                "設定", "偏好設定",
                // Thai
                "การตั้งค่า",
                // Vietnamese
                "Cài đặt", "Tùy chọn",
                // Indonesian
                "Pengaturan", "Setelan", "Preferensi",
                // Malay
                "Tetapan", "Keutamaan",
                // Filipino
                "Mga Setting", "Mga Kagustuhan",
                // Hindi
                "सेटिंग", "प्राथमिकताएं",
                // Bengali
                "সেটিংস",
                // Tamil
                "அமைப்புகள்",
                // Catalan
                "Configuració", "Preferències",
                // Basque
                "Ezarpenak",
                // Galician
                "Configuración", "Preferencias",
            ]
            
            if let title = targetVC.title, settingsTitles.contains(title) {
                injectEeveeButton(into: targetVC)
                return
            }
            
            if className.contains("Settings") && !className.contains("Eevee") {
                injectEeveeButton(into: targetVC)
                return
            }
            
            // AGGIUNTA: controlla anche classi con "Profile"
            if className.contains("Profile") && !className.contains("Eevee") {
                injectEeveeButton(into: targetVC)
                return
            }
        }
        
        checkBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: checkBlock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: checkBlock) // secondo tentativo
    }
}
