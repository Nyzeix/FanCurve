import AppKit

@MainActor
final class ApplicationActivationController {
    static let shared = ApplicationActivationController()

    private var dashboardIsVisible = false

    private init() {}

    func dashboardDidAppear() {
        guard !dashboardIsVisible else { return }

        dashboardIsVisible = true
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func dashboardDidDisappear() {
        guard dashboardIsVisible else { return }

        dashboardIsVisible = false
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
