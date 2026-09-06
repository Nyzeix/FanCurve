import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var updateCoordinator: UpdateCoordinator

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

            updatesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 440)
        .padding(.vertical, 8)
        .alert(
            "Update available",
            isPresented: Binding(
                get: { updateCoordinator.isUpdatePromptVisible },
                set: { isPresented in
                    if !isPresented {
                        updateCoordinator.dismissUpdatePrompt()
                    }
                }
            )
        ) {
            Button("Later", role: .cancel) {
                updateCoordinator.dismissUpdatePrompt()
            }
            Button("Install Update") {
                installUpdate()
            }
        } message: {
            Text(updateMessage)
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        Section {
            LabeledContent("Current version", value: updateCoordinator.currentVersion.description)

            Toggle(
                "Automatically check for updates",
                isOn: Binding(
                    get: { updateCoordinator.automaticallyChecksForUpdates },
                    set: { updateCoordinator.setAutomaticChecksEnabled($0) }
                )
            )

            if let lastCheckDate = updateCoordinator.lastCheckDate {
                Text("Last checked \(lastCheckDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            updateStatus

            Button("Check for Updates…") {
                updateCoordinator.checkForUpdates()
            }
            .disabled(updateCoordinator.isBusy)

            if updateCoordinator.availableRelease != nil {
                Button("Install Update") {
                    installUpdate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateCoordinator.isBusy)
            }
        } header: {
            Text("Updates")
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateCoordinator.state {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .upToDate:
            Label("FanCurve is up to date.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .available(let release):
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(verbatim: "FanCurve \(release.version) is available.")
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
                    .foregroundStyle(.blue)
                if !release.releaseNotes.isEmpty {
                    Text(release.releaseNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        case .downloading:
            Label("Downloading update…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .installing:
            Label("Installing update…", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        case .installed(let version):
            Label {
                Text(verbatim: "FanCurve \(version) was installed and will relaunch.")
            } icon: {
                Image(systemName: "checkmark.circle")
            }
                .foregroundStyle(.green)
        case .failed(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    private var updateMessage: String {
        guard let release = updateCoordinator.availableRelease else {
            return "A new FanCurve version is available."
        }
        return "FanCurve \(release.version) is available. Install it now?"
    }

    private func installUpdate() {
        Task {
            await updateCoordinator.installAvailableUpdate {
                await viewModel.prepareForApplicationUpdate()
            }
        }
    }
}
