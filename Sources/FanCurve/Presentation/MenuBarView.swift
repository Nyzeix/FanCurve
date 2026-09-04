import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var viewModel: FanControlViewModel
    @State private var displayedSnapshot = SystemSnapshot.empty

    var body: some View {
        Group {
            switch viewModel.menuBarPreferences.displayMode {
            case .temperatureIcon:
                Image(systemName: "thermometer.medium")
                    .accessibilityLabel(labelText)
            case .temperatureAndRPM:
                HStack(spacing: 5) {
                    Image(systemName: "wind")
                    Text(labelText)
                        .monospacedDigit()
                }
            }
        }
        .help("FanCurve")
        .task(id: viewModel.menuBarPreferences.updateInterval) {
            while !Task.isCancelled {
                displayedSnapshot = viewModel.snapshot

                do {
                    try await Task.sleep(for: viewModel.menuBarPreferences.updateInterval.duration)
                } catch {
                    return
                }
            }
        }
    }

    private var labelText: String {
        let formatter = TemperatureFormatter(unit: viewModel.menuBarPreferences.temperatureUnit)
        let temperature = formatter.string(fromCelsius: displayedSnapshot.referenceTemperature)
        let totalFanRPM = displayedSnapshot.fans.map(\.currentRPM).reduce(0, +)
        return "\(temperature) · \(totalFanRPM) RPM"
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: FanControlViewModel
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
