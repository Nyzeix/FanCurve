import Combine

struct MenuBarPresentation: Equatable {
    let displayMode: MenuBarDisplayMode
    let text: String
}

@MainActor
final class MenuBarStatusModel: ObservableObject {
    @Published private(set) var presentation = MenuBarPresentation(
        displayMode: .temperatureAndRPM,
        text: "— · 0 RPM"
    )

    func update(snapshot: SystemSnapshot, preferences: MenuBarPreferences) {
        let text: String
        switch preferences.displayMode {
        case .temperatureIcon:
            text = "FanCurve"
        case .temperatureAndRPM:
            let temperature = TemperatureFormatter(unit: preferences.temperatureUnit)
                .string(fromCelsius: snapshot.referenceTemperature)
            let rpm = snapshot.fans.reduce(0) { $0 + $1.currentRPM }
            text = "\(temperature) · \(rpm) RPM"
        }
        let next = MenuBarPresentation(displayMode: preferences.displayMode, text: text)
        if presentation != next {
            presentation = next
        }
    }
}
