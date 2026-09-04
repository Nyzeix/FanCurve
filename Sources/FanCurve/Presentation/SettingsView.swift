import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel

    var body: some View {
        Form {
            Section {
                Picker(
                    "Refresh rate",
                    selection: Binding(
                        get: { viewModel.menuBarPreferences.updateInterval },
                        set: { viewModel.setMenuBarUpdateInterval($0) }
                    )
                ) {
                    ForEach(MenuBarUpdateInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }

                Text("How often the temperature and fan speed are refreshed in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            } header: {
                Text("Menu bar")
            }

            Section {
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

                Text("The selected unit is used throughout FanCurve, including the dashboard and curve editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Temperature")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440)
        .padding(.vertical, 8)
    }
}
