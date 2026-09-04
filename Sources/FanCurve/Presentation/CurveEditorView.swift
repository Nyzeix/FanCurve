import Charts
import SwiftUI

struct CurveEditorView: View {
    @ObservedObject var viewModel: FanControlViewModel

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

                Picker("Source", selection: $viewModel.curve.source) {
                    ForEach(CurveTemperatureSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .frame(width: 210)
            }

            Label(
                "0 RPM is available from \(temperatureFormatter.string(fromCelsius: FanCurveTemperatureLimits.minimum)). Other targets must respect the hardware minimum.",
                systemImage: "thermometer.medium"
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(viewModel.curve.points) { point in
                LineMark(
                    x: .value("Temperature", point.temperature),
                    y: .value("Speed", point.targetRPM)
                )
                .foregroundStyle(.blue.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Temperature", point.temperature),
                    y: .value("Speed", point.targetRPM)
                )
                .foregroundStyle(.blue)
                .symbolSize(75)
            }
            .chartXScale(domain: 35...105)
            .chartYScale(domain: 0...viewModel.fanLimits.maximumRPM)
            .chartXAxis {
                AxisMarks(values: temperatureUnit.chartTickValues) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let celsius = value.as(Double.self) {
                            Text(temperatureFormatter.string(fromCelsius: celsius, includesUnit: false))
                        }
                    }
                }
            }
            .chartXAxisLabel("Temperature (\(temperatureUnit.symbol))")
            .chartYAxisLabel("Speed (RPM)")
            .frame(height: 230)
            .padding(.horizontal, 4)

            Divider()

            ForEach($viewModel.curve.points) { $point in
                HStack(spacing: 12) {
                    Text(temperatureFormatter.string(fromCelsius: point.temperature))
                        .font(.body.monospacedDigit())
                        .frame(width: 70, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { temperatureUnit.displayValue(fromCelsius: point.temperature) },
                            set: { point.temperature = temperatureUnit.celsiusValue(fromDisplayed: $0) }
                        ),
                        in: temperatureUnit.displayedCurveRange,
                        step: 1
                    )

                    Text("\(point.targetRPM) RPM")
                        .font(.body.monospacedDigit())
                        .frame(width: 110, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { Double(point.targetRPM) },
                            set: { point.targetRPM = Int($0.rounded()) }
                        ),
                        in: 0...Double(viewModel.fanLimits.maximumRPM),
                        step: 50
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
    }

    private var temperatureUnit: TemperatureUnit {
        viewModel.menuBarPreferences.temperatureUnit
    }

    private var temperatureFormatter: TemperatureFormatter {
        TemperatureFormatter(unit: temperatureUnit)
    }
}
