import AppKit

@MainActor
final class ApplicationMenuController: NSObject, NSApplicationDelegate {
    private var menuObserver: NSObjectProtocol?

    override init() {
        super.init()

        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeUnusedMenusWhenReady()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        removeUnusedMenusWhenReady()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        removeUnusedMenusWhenReady()
    }

    private func removeUnusedMenusWhenReady() {
        DispatchQueue.main.async { [weak self] in
            self?.removeUnusedMenus()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.removeUnusedMenus()
        }
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
