import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var status: MenuBarStatusModel

    var body: some View {
        Group {
            switch status.presentation.displayMode {
            case .temperatureIcon:
                Image(systemName: "thermometer.medium")
                    .accessibilityLabel(status.presentation.text)
            case .temperatureAndRPM:
                HStack(spacing: 5) {
                    Image(systemName: "wind")
                    Text(status.presentation.text)
                        .monospacedDigit()
                }
            }
        }
        .help("FanCurve")
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var updateCoordinator: UpdateCoordinator
    @Environment(\.openWindow) private var openWindow

    private let menuBarPopoverWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FanCurve")
                .font(.headline)

            Divider()

            metricRow("CPU", value: temperatureText(viewModel.snapshot.cpuTemperature), icon: "cpu")
            metricRow("GPU", value: temperatureText(viewModel.snapshot.gpuTemperature), icon: "rectangle.3.group")
            metricRow("Battery", value: temperatureText(viewModel.snapshot.batteryTemperature), icon: "battery.75")

            ForEach(viewModel.snapshot.fans) { fan in
                metricRow(fanMenuTitle(for: fan), value: "\(fan.currentRPM) RPM", icon: "wind")
            }

            Divider()

            if let release = updateCoordinator.availableRelease {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label {
                        Text(verbatim: "FanCurve \(release.version) is available")
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }

            Toggle(
                "Custom control",
                isOn: Binding(
                    get: { viewModel.isControlEnabled },
                    set: { viewModel.setControlEnabled($0) }
                )
            )
            .disabled(!viewModel.capabilities.canControlFans)

            if !viewModel.capabilities.isSimulated && !viewModel.capabilities.canControlFans {
                Button("Enable hardware control", systemImage: "lock.open") {
                    viewModel.installHelper()
                }
            }

            Button("Open FanCurve", systemImage: "macwindow") {
                openWindow(id: "dashboard")
            }

            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: menuBarPopoverWidth)
        .background {
            WindowVisibilityObserver { viewModel.setMenuBarVisible($0) }
                .frame(width: 0, height: 0)
        }
        .onDisappear { viewModel.setMenuBarVisible(false) }
    }

    private func metricRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }

    private func fanMenuTitle(for fan: FanSnapshot) -> String {
        fan.name == "Left fan" ? "Fan speed" : fan.name
    }

    private func temperatureText(_ temperature: Double?) -> String {
        TemperatureFormatter(unit: viewModel.menuBarPreferences.temperatureUnit)
            .string(fromCelsius: temperature)
    }
}
