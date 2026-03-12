import Orion
import SwiftUI
import UIKit

// Universal settings integration that works across all Spotify versions
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
    let image = UIImage(systemName: "gearshape.fill") ?? UIImage()
    button.setImage(image, for: .normal)
    button.tintColor = .white
    
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

// MARK: - Fallback: Hook SettingsViewController directly (New UI)
class SettingsViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "SettingsViewController"

    func viewDidLoad() {
        orig.viewDidLoad()
        injectEeveeButton(into: target)
    }

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        injectEeveeButton(into: target)
    }
}

// MARK: - Fallback: Hook RootSettingsViewController directly
class RootSettingsViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "RootSettingsViewController"

    func viewDidLoad() {
        orig.viewDidLoad()
        injectEeveeButton(into: target)
    }

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        injectEeveeButton(into: target)
    }
}

// MARK: - Generic Fallback: Hook UINavigationController to catch Settings by title/class name
class SettingsNavigationStackHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup

    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        
        let targetVC = viewController
        
        let checkBlock = {
            let className = String(describing: type(of: targetVC))
            
            // Localized "Settings" / "Preferences" titles
            let settingsTitles: Set<String> = [
                "Settings", "Preferences",
                "Einstellungen", "Präferenzen",
                "Paramètres", "Préférences",
                "Configuración", "Ajustes", "Preferencias",
                "Impostazioni", "Preferenze",
                "Definições", "Configurações", "Preferências",
                "Instellingen", "Voorkeuren",
                "Ayarlar", "Tercihler",
                "Ustawienia", "Preferencje",
                "Настройки", "Параметры",
                "Налаштування", "Параметри",
                "Nastavení", "Předvolby",
                "Inställningar",
                "Innstillinger",
                "Indstillinger",
                "Asetukset",
                "Beállítások",
                "Setări", "Preferințe",
                "Nastavenia",
                "Postavke", "Podešavanja",
                "Nastavitve",
                "Настройки",
                "Ρυθμίσεις", "Προτιμήσεις",
                "הגדרות", "העדפות",
                "الإعدادات", "التفضيلات",
                "تنظیمات", "ترجیحات",
                "設定", "環境設定",
                "설정", "환경설정",
                "设置", "偏好设置",
                "設定", "偏好設定",
                "การตั้งค่า",
                "Cài đặt", "Tùy chọn",
                "Pengaturan", "Setelan", "Preferensi",
                "Tetapan", "Keutamaan",
                "Mga Setting", "Mga Kagustuhan",
                "सेटिंग", "प्राथमिकताएं",
                "সেটিংস",
                "அமைப்புகள்",
                "Configuració", "Preferències",
                "Ezarpenak",
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
        }
        
        checkBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: checkBlock)
    }
}
