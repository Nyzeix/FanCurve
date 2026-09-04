import SwiftUI

@main
struct FanCurveApp: App {
    @StateObject private var viewModel = FanControlViewModel()
    @NSApplicationDelegateAdaptor(ApplicationMenuController.self)
    private var applicationMenuController

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            DashboardView(viewModel: viewModel)
        }
        .defaultSize(width: 860, height: 700)
        .commands {
            FanCurveCommands()
        }

        Window("FanCurve Help", id: "help") {
            HelpView(viewModel: viewModel)
        }
        .defaultSize(width: 600, height: 600)

        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct FanCurveCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("How FanCurve works") {
                openWindow(id: "help")
            }
        }
    }
}
