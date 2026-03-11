import Orion
import SwiftUI
import UIKit
import Foundation

// Universal settings integration group (tutti gli hook appartengono a questo gruppo)
struct UniversalSettingsIntegrationGroup: HookGroup { }

// MARK: - Primary: ProfileSettingsSection hook for settings menu row
class UniversalProfileSettingsSectionHook: ClassHook<NSObject> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "ProfileSettingsSection"
    
    func numberOfRows() -> Int {
        let original = orig.numberOfRows()
        return original + 1
    }
    
    func didSelectRow(_ row: Int) {
        let originalRows = orig.numberOfRows()
        
        if row == originalRows {
            openEeveeSettingsFromHook()
            return
        }
        
        orig.didSelectRow(row)
    }
    
    func cellForRow(_ row: Int) -> UITableViewCell {
        let originalRows = orig.numberOfRows()
        
        if row == originalRows {
            let settingsTableCell = Dynamic.SPTSettingsTableViewCell
                .alloc(interface: SPTSettingsTableViewCell.self)
                .initWithStyle(3, reuseIdentifier: "EeveeSpotify")
            
            let tableViewCell = Dynamic.convert(settingsTableCell, to: UITableViewCell.self)
            
            tableViewCell.accessoryView = type(
                of: Dynamic.SPTDisclosureAccessoryView
                    .alloc(interface: SPTDisclosureAccessoryView.self)
            )
            .disclosureAccessoryView()
            
            tableViewCell.textLabel?.text = "EeveeSpotify"
            
            return tableViewCell
        }
        
        return orig.cellForRow(row)
    }
    
    private func openEeveeSettingsFromHook() {
        // Try to find the root settings controller
        let rootSettingsController = WindowHelper.shared.findFirstViewController("RootSettingsViewController")
            ?? WindowHelper.shared.findFirstViewController("SettingsViewController")
            ?? WindowHelper.shared.findFirstViewController("ProfileViewController")
        
        guard let rootController = rootSettingsController,
              let navigationController = rootController.navigationController else {
            return
        }
        
        let eeveeSettingsController = EeveeSettingsViewController(
            rootController.view.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: navigationController)),
            navigationTitle: "EeveeSpotify"
        )
        
        navigationController.pushViewController(eeveeSettingsController, animated: true)
    }
}

// MARK: - Global Helper to avoid Orion Hooking Issues with setupEeveeButton
func injectEeveeButton(into target: UIViewController) {
    // Check if the button already exists in rightBarButtonItems
    if let rightItems = target.navigationItem.rightBarButtonItems,
       rightItems.contains(where: { $0.tag == 1337 }) {
        return
    }
    
    let button = UIButton(type: .system)
    // Usa alwaysOriginal per mantenere il colore bianco anche in contesti con tint
    let image = UIImage(systemName: "gearshape.fill")?.withRenderingMode(.alwaysOriginal)
    button.setImage(image, for: .normal)
    button.tintColor = .white // Forza bianco per visibilità su sfondi scuri
    
    let action = UIAction { [weak target] _ in
        guard let target = target, let navigationController = target.navigationController else { return }
        
        let eeveeSettingsController = EeveeSettingsViewController(
            target.view.bounds,
            settingsView: AnyView(EeveeSettingsView(navigationController: navigationController)),
            navigationTitle: "EeveeSpotify"
        )
        
        navigationController.pushViewController(eeveeSettingsController, animated: true)
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

// MARK: - Fallback hooks (attivi solo se ProfileSettingsSection non esiste)

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

// AGGIUNTO: Hook per ProfileViewController (spesso root delle impostazioni)
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
            
            // Lista completa dei titoli (come nell'originale)
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
            
            // Controlla anche classi che contengono "Settings" o "Profile"
            if (className.contains("Settings") || className.contains("Profile")) && !className.contains("Eevee") {
                injectEeveeButton(into: targetVC)
                return
            }
        }
        
        checkBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: checkBlock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: checkBlock) // Secondo tentativo
    }
}
