import Foundation

enum TemperatureUnit: String, CaseIterable, Codable, Hashable, Sendable {
    case celsius
    case fahrenheit

    var displayName: String {
        switch self {
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    var displayedCurveRange: ClosedRange<Double> {
        let minimum = displayValue(fromCelsius: FanCurveTemperatureLimits.minimum)
        let maximum = displayValue(fromCelsius: FanCurveTemperatureLimits.maximum)
        return minimum...maximum
    }

    var chartTickValues: [Double] {
        [35, 50, 65, 80, 95, 105]
    }

    func displayValue(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius:
            celsius
        case .fahrenheit:
            celsius * 9 / 5 + 32
        }
    }

    func celsiusValue(fromDisplayed value: Double) -> Double {
        switch self {
        case .celsius:
            value
        case .fahrenheit:
            (value - 32) * 5 / 9
        }
    }

    func string(fromCelsius celsius: Double?, includesUnit: Bool = true) -> String {
        guard let celsius else { return "—" }

        let value = Int(displayValue(fromCelsius: celsius).rounded())
        return includesUnit ? "\(value) \(symbol)" : "\(value)"
    }
}

struct TemperatureFormatter: Sendable {
    let unit: TemperatureUnit

    func string(fromCelsius celsius: Double?, includesUnit: Bool = true) -> String {
        unit.string(fromCelsius: celsius, includesUnit: includesUnit)
    }
}
