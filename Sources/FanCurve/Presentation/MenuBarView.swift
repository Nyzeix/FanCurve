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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FanCurve")
                .font(.headline)

            Divider()

            metricRow("CPU", value: temperatureText(viewModel.snapshot.cpuTemperature), icon: "cpu")
            metricRow("GPU", value: temperatureText(viewModel.snapshot.gpuTemperature), icon: "rectangle.3.group")
            metricRow("Battery", value: temperatureText(viewModel.snapshot.batteryTemperature), icon: "battery.75")

            ForEach(viewModel.snapshot.fans) { fan in
                metricRow(fan.name, value: "\(fan.currentRPM) RPM", icon: "wind")
            }

            Divider()

            Text("Status bar")
                .font(.headline)

            Picker(
                "Refresh",
                selection: Binding(
                    get: { viewModel.menuBarPreferences.updateInterval },
                    set: { viewModel.setMenuBarUpdateInterval($0) }
                )
            ) {
                ForEach(MenuBarUpdateInterval.allCases, id: \.self) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }

            Picker(
                "Display",
                selection: Binding(
                    get: { viewModel.menuBarPreferences.displayMode },
                    set: { viewModel.setMenuBarDisplayMode($0) }
                )
            ) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker(
                "Temperature unit",
                selection: Binding(
                    get: { viewModel.menuBarPreferences.temperatureUnit },
                    set: { viewModel.setTemperatureUnit($0) }
                )
            ) {
                ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
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

            Button("FanCurve Help", systemImage: "questionmark.circle") {
                openWindow(id: "help")
            }

            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 280)
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

    private func temperatureText(_ temperature: Double?) -> String {
        TemperatureFormatter(unit: viewModel.menuBarPreferences.temperatureUnit)
            .string(fromCelsius: temperature)
    }
}
