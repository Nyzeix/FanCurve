import SwiftUI

struct FanCurveChartView: View {
    let points: [FanCurvePoint]
    let maximumRPM: Int
    let temperatureUnit: TemperatureUnit

    private let temperatureTicks = [35.0, 50, 65, 80, 95, 105]
    private let verticalTickFractions = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        VStack(spacing: 4) {
            Text("Speed (RPM)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Canvas(opaque: false, colorMode: .linear) { context, size in
                drawChart(in: &context, size: size)
            }
            .frame(height: 190)

            Text("Temperature (\(temperatureUnit.symbol))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan curve chart")
    }

    private func drawChart(in context: inout GraphicsContext, size: CGSize) {
        let plotRect = CGRect(
            x: 54,
            y: 10,
            width: max(size.width - 74, 1),
            height: max(size.height - 36, 1)
        )
        let gridColor = Color.secondary.opacity(0.2)

        for fraction in verticalTickFractions {
            let y = plotRect.maxY - plotRect.height * fraction
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: plotRect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.stroke(gridPath, with: .color(gridColor), lineWidth: 1)

            let rpmValue = Int((Double(maximumRPM) * fraction).rounded())
            let label = context.resolve(
                Text(rpmValue.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            )
            context.draw(label, at: CGPoint(x: plotRect.minX - 8, y: y), anchor: .trailing)
        }

        for temperature in temperatureTicks {
            let x = xPosition(for: temperature, in: plotRect)
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: x, y: plotRect.minY))
            gridPath.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            context.stroke(gridPath, with: .color(gridColor), lineWidth: 1)

            let displayedTemperature = Int(
                temperatureUnit.displayValue(fromCelsius: temperature).rounded()
            )
            let label = context.resolve(
                Text(displayedTemperature.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            )
            context.draw(
                label,
                at: CGPoint(x: x, y: plotRect.maxY + 15),
                anchor: .center
            )
        }

        let sortedPoints = points.sorted { $0.temperature < $1.temperature }
        guard let firstPoint = sortedPoints.first else { return }

        var curvePath = Path()
        curvePath.move(to: pointPosition(for: firstPoint, in: plotRect))
        for point in sortedPoints.dropFirst() {
            curvePath.addLine(to: pointPosition(for: point, in: plotRect))
        }
        context.stroke(
            curvePath,
            with: .color(.blue),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )

        for point in sortedPoints {
            let position = pointPosition(for: point, in: plotRect)
            let marker = CGRect(x: position.x - 5, y: position.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: marker), with: .color(.blue))
            context.stroke(Path(ellipseIn: marker), with: .color(Color.primary), lineWidth: 2)
        }
    }

    private func pointPosition(for point: FanCurvePoint, in plotRect: CGRect) -> CGPoint {
        let boundedTemperature = min(max(point.temperature, 35), 105)
        let boundedRPM = min(max(point.targetRPM, 0), max(maximumRPM, 1))
        return CGPoint(
            x: xPosition(for: boundedTemperature, in: plotRect),
            y: plotRect.maxY - plotRect.height * CGFloat(boundedRPM) / CGFloat(max(maximumRPM, 1))
        )
    }

    private func xPosition(for temperature: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.minX + plotRect.width * CGFloat(temperature - 35) / 70
    }
}
