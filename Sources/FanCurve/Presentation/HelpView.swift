import SwiftUI

struct HelpView: View {
    @ObservedObject var viewModel: FanControlViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                helpSection(
                    title: "Monitoring",
                    systemImage: "waveform.path.ecg",
                    text: "FanCurve regularly reads CPU, GPU, and battery temperatures, along with fan speed. The highest CPU or GPU temperature is used as the default reference."
                )
                helpSection(
                    title: "Custom curve",
                    systemImage: "chart.xyaxis.line",
                    text: "Each point associates a temperature with a target speed. FanCurve interpolates values between points and applies the curve only when the Custom control switch is enabled."
                )
                helpSection(
                    title: "Profiles",
                    systemImage: "square.stack.3d.up",
                    text: "Quiet, Normal, and Aggressive Cooling are available by default. Each profile stores its own curve, and you can create, rename, delete, and customize profiles from the curve editor."
                )
                helpSection(
                    title: "Stop at 0 RPM",
                    systemImage: "pause.circle",
                    text: "A target of 0 RPM can be selected in the curve from \(temperatureFormatter.string(fromCelsius: FanCurveTemperatureLimits.minimum)). Non-zero speeds must start at 2,350 RPM and remain within the fan's reported maximum."
                )
                helpSection(
                    title: "Return control to macOS",
                    systemImage: "arrow.uturn.backward.circle",
                    text: "When Custom control is disabled, or if FanCurve encounters a hardware error, fan control is returned to macOS."
                )
                helpSection(
                    title: "Status bar",
                    systemImage: "menubar.arrow.up.rectangle",
                    text: "Open Settings from the macOS menu bar, or from the FanCurve menu, to choose the refresh rate, status bar display, and temperature unit."
                )
                helpSection(
                    title: "Updates",
                    systemImage: "arrow.down.circle",
                    text: "FanCurve checks the official GitHub release periodically. A new version is never installed without your confirmation. Before updating, FanCurve returns fan control to macOS and keeps Custom control disabled after relaunch."
                )

                Label(
                    "The privileged helper is required to write hardware commands. The Mac's thermal protections remain the priority.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FanCurve Help")
                .font(.largeTitle.weight(.bold))
            Text("Understand how FanCurve monitors and controls your fans.")
                .foregroundStyle(.secondary)
        }
    }

    private var temperatureFormatter: TemperatureFormatter {
        TemperatureFormatter(unit: viewModel.menuBarPreferences.temperatureUnit)
    }

    private func helpSection(title: String, systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
