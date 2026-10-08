import AppKit

@MainActor
final class ApplicationMenuController: NSObject, NSApplicationDelegate {
    private var menuCleanupWorkItem: DispatchWorkItem?

    override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        removeUnusedMenusWhenReady()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        removeUnusedMenusWhenReady()
    }

    private func removeUnusedMenusWhenReady() {
        menuCleanupWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.removeUnusedMenus()
        }
        menuCleanupWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func removeUnusedMenus() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }

        let applicationMenuTitle = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleName"
        ) as? String ?? ProcessInfo.processInfo.processName

        let allowedMenuTitles = Set([applicationMenuTitle, "Settings", "Help"])
        mainMenu.items
            .filter { !allowedMenuTitles.contains($0.title) }
            .forEach(mainMenu.removeItem)
    }
}
