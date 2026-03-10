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
}

class SettingsNavigationStackHook: ClassHook<UINavigationController> {
    typealias Group = UniversalSettingsIntegrationGroup

    func pushViewController(_ viewController: UIViewController, animated: Bool) {
        orig.pushViewController(viewController, animated: animated)
        
        guard NSClassFromString("ProfileSettingsSection") == nil else { return }
        
        let targetVC = viewController
        
        let checkBlock = {
            let className = String(describing: type(of: targetVC))
            
            if let title = targetVC.title, title == "Settings" {
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
