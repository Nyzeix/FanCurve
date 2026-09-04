import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: FanControlViewModel

    private let metricColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metrics
                CurveEditorView(viewModel: viewModel)
                footer
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 720, minHeight: 600)
        .onAppear {
            viewModel.start()
            ApplicationActivationController.shared.dashboardDidAppear()
        }
        .onDisappear {
            ApplicationActivationController.shared.dashboardDidDisappear()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FanCurve")
                    .font(.largeTitle.weight(.bold))
                Text("Monitor and adjust your Mac's cooling.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Toggle(
                    "Custom control",
                    isOn: Binding(
                        get: { viewModel.isControlEnabled },
                        set: { viewModel.setControlEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!viewModel.capabilities.canControlFans)

                Label(viewModel.status.displayName, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)

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
                .pickerStyle(.menu)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: metricColumns, spacing: 12) {
            MetricCard(
                title: "CPU",
                value: temperatureText(viewModel.snapshot.cpuTemperature),
                systemImage: "cpu",
                tint: .orange
            )
            MetricCard(
                title: "GPU",
                value: temperatureText(viewModel.snapshot.gpuTemperature),
                systemImage: "rectangle.3.group",
                tint: .purple
            )
            MetricCard(
                title: "Battery",
                value: temperatureText(viewModel.snapshot.batteryTemperature),
                systemImage: "battery.75",
                tint: .green
            )
            MetricCard(
                title: "Fans",
                value: "\(viewModel.totalFanRPM) RPM",
                systemImage: "wind",
                tint: .blue
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if !viewModel.capabilities.message.isEmpty {
                Text(viewModel.capabilities.message)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.capabilities.isSimulated && !viewModel.capabilities.canControlFans {
                Button("Enable hardware control", systemImage: "lock.open") {
                    viewModel.installHelper()
                }
            }

            HStack {
                Label(
                    "Thermal state: \(viewModel.snapshot.thermalCondition.displayName)",
                    systemImage: "thermometer.medium"
                )
                .foregroundStyle(.secondary)

                Spacer()

                Text("macOS thermal protections remain the priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var statusIcon: String {
        switch viewModel.status {
        case .active: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .unavailable: "nosign"
        default: "circle.fill"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .active: .green
        case .error: .red
        case .unavailable: .orange
        default: .secondary
        }
    }

    private func temperatureText(_ temperature: Double?) -> String {
        TemperatureFormatter(unit: viewModel.menuBarPreferences.temperatureUnit)
            .string(fromCelsius: temperature)
    }
}
