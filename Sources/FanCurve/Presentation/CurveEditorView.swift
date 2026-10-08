import SwiftUI

struct CurveEditorView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @State private var profileEditor: ProfileEditorMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fan curve")
                        .font(.headline)
                    Text("Speed is interpolated between each point.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                profilePicker

                Picker("Source", selection: $viewModel.curve.source) {
                    ForEach(CurveTemperatureSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .frame(width: 210)
            }

            Label(
                "0 RPM is available from \(temperatureFormatter.string(fromCelsius: FanCurveTemperatureLimits.minimum)). Non-zero targets must be at least \(FanCurveRPMPolicy.minimumNonZeroRPM) RPM and respect the hardware maximum.",
                systemImage: "thermometer.medium"
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            FanCurveChartView(
                points: viewModel.curve.points,
                maximumRPM: viewModel.fanLimits.maximumRPM,
                temperatureUnit: temperatureUnit
            )

            Divider()

            ForEach($viewModel.curve.points) { $point in
                HStack(spacing: 12) {
                    Text(temperatureFormatter.string(fromCelsius: point.temperature))
                        .font(.body.monospacedDigit())
                        .frame(width: 70, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { temperatureUnit.displayValue(fromCelsius: point.temperature) },
                            set: {
                                point.temperature = temperatureUnit.celsiusValue(fromDisplayed: $0.rounded())
                            }
                    ),
                        in: temperatureUnit.displayedCurveRange
                    )

                    Text("\(point.targetRPM) RPM")
                        .font(.body.monospacedDigit())
                        .frame(width: 110, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { rpmSliderPosition(for: point.targetRPM) },
                            set: { point.targetRPM = targetRPM(for: $0) }
                        ),
                        in: 0...rpmSliderMaximum
                    )
                }
            }

            HStack {
                Button("Add point", systemImage: "plus") {
                    viewModel.addPoint()
                }
                .disabled(viewModel.curve.points.count >= 12)

                Button("Recommended curve", systemImage: "arrow.counterclockwise") {
                    viewModel.restoreRecommendedCurve()
                }

                Spacer()

                Button("Cancel") {
                    viewModel.restoreSavedCurve()
                }

                Button("Save") {
                    viewModel.saveCurve()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .sheet(item: $profileEditor) { editor in
            ProfileEditorView(
                title: editor.title,
                actionTitle: editor.actionTitle,
                initialName: editor.initialName
            ) { name in
                switch editor {
                case .create:
                    viewModel.createProfile(named: name)
                case .rename:
                    viewModel.renameActiveProfile(to: name)
                }
            }
        }
    }

    private var profilePicker: some View {
        HStack(spacing: 6) {
            Picker("Profile", selection: Binding(
                get: { viewModel.activeProfileID },
                set: { viewModel.selectProfile($0) }
            )) {
                ForEach(viewModel.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .frame(width: 170)

            Menu {
                Button("New Profile", systemImage: "plus") {
                    profileEditor = .create
                }

                Button("Rename Profile", systemImage: "pencil") {
                    profileEditor = .rename(viewModel.activeProfileName)
                }

                Divider()

                Button("Delete Profile", systemImage: "trash", role: .destructive) {
                    viewModel.deleteActiveProfile()
                }
                .disabled(viewModel.profiles.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .help("Manage profiles")
        }
    }

    private var temperatureUnit: TemperatureUnit {
        viewModel.menuBarPreferences.temperatureUnit
    }

    private var temperatureFormatter: TemperatureFormatter {
        TemperatureFormatter(unit: temperatureUnit)
    }

    private var rpmSliderMaximum: Double {
        let minimum = FanCurveRPMPolicy.minimumNonZeroRPM(for: viewModel.fanLimits)
        let maximum = viewModel.fanLimits.maximumRPM
        guard maximum >= minimum else { return 0 }

        let nonZeroSteps = (maximum - minimum + 49) / 50
        return Double(nonZeroSteps + 1)
    }

    private func rpmSliderPosition(for rpm: Int) -> Double {
        guard rpm > 0 else { return 0 }

        let minimum = FanCurveRPMPolicy.minimumNonZeroRPM(for: viewModel.fanLimits)
        let steps = max(0, Int(Double(rpm - minimum).rounded() / 50))
        return min(Double(steps + 1), rpmSliderMaximum)
    }

    private func targetRPM(for sliderPosition: Double) -> Int {
        guard sliderPosition >= 0.5 else { return 0 }

        let minimum = FanCurveRPMPolicy.minimumNonZeroRPM(for: viewModel.fanLimits)
        let maximum = viewModel.fanLimits.maximumRPM
        guard maximum >= minimum else { return 0 }

        let steps = max(0, Int(sliderPosition.rounded()) - 1)
        return min(minimum + steps * 50, maximum)
    }
}

private enum ProfileEditorMode: Identifiable {
    case create
    case rename(String)

    var id: String {
        switch self {
        case .create: "create"
        case .rename: "rename"
        }
    }

    var title: String {
        switch self {
        case .create: "New Profile"
        case .rename: "Rename Profile"
        }
    }

    var actionTitle: String {
        switch self {
        case .create: "Create"
        case .rename: "Save"
        }
    }

    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let name): name
        }
    }
}
