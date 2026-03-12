import Orion
import SwiftUI
import UIKit

struct UniversalSettingsIntegrationGroup: HookGroup { }

// MARK: - Helper per cercare la riga di Eevee nella tabella
func isEeveeRowPresent(in view: UIView) -> Bool {
    if let tableView = view as? UITableView {
        for cell in tableView.visibleCells {
            // Controlla se il testo della cella è "EeveeSpotify"
            if let textLabel = cell.textLabel, textLabel.text == "EeveeSpotify" {
                return true
            }
            // Alcune celle potrebbero avere la label in una gerarchia diversa; 
            // proviamo anche a cercare ricorsivamente nella cella stessa
            if isEeveeRowPresent(in: cell) {
                return true
            }
        }
    }
    for subview in view.subviews {
        if isEeveeRowPresent(in: subview) {
            return true
        }
    }
    return false
}

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

// MARK: - Helper per iniettare il bottone (con controllo presenza riga)
func injectEeveeButton(into target: UIViewController) {
    // Se la riga "EeveeSpotify" è già presente nella tabella, non iniettare la rotella
    if isEeveeRowPresent(in: target.view) {
        return
    }
    
    // Evita duplicati
    if let items = target.navigationItem.rightBarButtonItems,
       items.contains(where: { $0.tag == 1337 }) {
        return
    }
    
    let button = UIButton(type: .system)
    let image = UIImage(systemName: "gearshape.fill")?.withRenderingMode(.alwaysOriginal)
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

// MARK: - Fallback hooks (sempre attivi, ma controllano la presenza della riga)
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
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        injectEeveeButton(into: target)
    }
}

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
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        injectEeveeButton(into: target)
    }
}

class ProfileViewControllerHook: ClassHook<UIViewController> {
    typealias Group = UniversalSettingsIntegrationGroup
    static let targetName = "ProfileViewController"

    func viewDidLoad() {
        orig.viewDidLoad()
        injectEeveeButton(into: target)
    }

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        injectEeveeButton(into: target)
    }
    
    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        injectEeveeButton(into: target)
    }
}

class SettingsNavigationStackHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup

    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        
        let targetVC = viewController
        
        let checkBlock = {
            let className = String(describing: type(of: targetVC))
            
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
            
            if className.contains("Profile") && !className.contains("Eevee") {
                injectEeveeButton(into: targetVC)
                return
            }
        }
        
        checkBlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: checkBlock)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: checkBlock)
    }
}
