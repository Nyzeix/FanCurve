import Foundation

enum MonitoringPolicy {
    static func interval(
        controlEnabled: Bool,
        readingsVisible: Bool,
        displayMode: MenuBarDisplayMode,
        refreshInterval: MenuBarUpdateInterval,
        suspended: Bool,
        displayAwake: Bool = true
    ) -> Duration? {
        guard !suspended else { return nil }
        if controlEnabled {
            return .seconds(1)
        }
        guard displayAwake else { return nil }
        if readingsVisible { return .seconds(1) }
        return displayMode == .temperatureAndRPM ? refreshInterval.duration : nil
    }
}
