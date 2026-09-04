import Foundation

struct FanIdentifier: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    var description: String { rawValue }
}

struct FanLimits: Codable, Equatable, Sendable {
    let minimumRPM: Int
    let maximumRPM: Int

    init(minimumRPM: Int, maximumRPM: Int) {
        self.minimumRPM = min(minimumRPM, maximumRPM)
        self.maximumRPM = max(minimumRPM, maximumRPM)
    }
}

struct FanSnapshot: Identifiable, Equatable, Sendable {
    let id: FanIdentifier
    let name: String
    let currentRPM: Int
    let limits: FanLimits
}

enum ThermalCondition: String, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Moderate"
        case .serious: "High"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }
}

struct SystemSnapshot: Equatable, Sendable {
    let capturedAt: Date
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let batteryTemperature: Double?
    let fans: [FanSnapshot]
    let thermalCondition: ThermalCondition
    let isSimulated: Bool

    static let empty = SystemSnapshot(
        capturedAt: .now,
        cpuTemperature: nil,
        gpuTemperature: nil,
        batteryTemperature: nil,
        fans: [],
        thermalCondition: .unknown,
        isSimulated: false
    )

    var referenceTemperature: Double? {
        [cpuTemperature, gpuTemperature].compactMap { $0 }.max()
    }
}

enum CurveTemperatureSource: String, CaseIterable, Codable, Sendable {
    case hottestProcessor
    case cpu
    case gpu

    var displayName: String {
        switch self {
        case .hottestProcessor: "Hottest CPU or GPU"
        case .cpu: "CPU"
        case .gpu: "GPU"
        }
    }
}

enum FanCurveTemperatureLimits {
    // macOS does not expose a numeric fan-start threshold. These bounds limit
    // the editable curve range and keep the lower bound used by the UI stable.
    static let minimum: Double = 35
    static let maximum: Double = 105
}

enum MenuBarUpdateInterval: Double, CaseIterable, Codable, Hashable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    var displayName: String {
        switch self {
        case .oneSecond: "1 second"
        case .twoSeconds: "2 seconds"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        }
    }

    var duration: Duration {
        .seconds(rawValue)
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Codable, Hashable, Sendable {
    case temperatureIcon
    case temperatureAndRPM

    var displayName: String {
        switch self {
        case .temperatureIcon: "Temperature icon"
        case .temperatureAndRPM: "Temperature · RPM"
        }
    }
}

struct MenuBarPreferences: Codable, Equatable, Sendable {
    var updateInterval: MenuBarUpdateInterval = .oneSecond
    var displayMode: MenuBarDisplayMode = .temperatureAndRPM
    var temperatureUnit: TemperatureUnit = .celsius

    private enum CodingKeys: String, CodingKey {
        case updateInterval
        case displayMode
        case temperatureUnit
    }

    init(
        updateInterval: MenuBarUpdateInterval = .oneSecond,
        displayMode: MenuBarDisplayMode = .temperatureAndRPM,
        temperatureUnit: TemperatureUnit = .celsius
    ) {
        self.updateInterval = updateInterval
        self.displayMode = displayMode
        self.temperatureUnit = temperatureUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updateInterval = try container.decodeIfPresent(MenuBarUpdateInterval.self, forKey: .updateInterval) ?? .oneSecond
        displayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .displayMode) ?? .temperatureAndRPM
        temperatureUnit = try container.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? .celsius
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updateInterval, forKey: .updateInterval)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(temperatureUnit, forKey: .temperatureUnit)
    }
}

struct FanCurvePoint: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var temperature: Double
    var targetRPM: Int

    init(id: UUID = UUID(), temperature: Double, targetRPM: Int) {
        self.id = id
        self.temperature = temperature
        self.targetRPM = targetRPM
    }
}

struct FanCurve: Codable, Equatable, Sendable {
    var points: [FanCurvePoint]
    var source: CurveTemperatureSource

    static func recommended(limits: FanLimits) -> FanCurve {
        let minimum = limits.minimumRPM
        let maximum = limits.maximumRPM
        let range = maximum - minimum

        return FanCurve(
            points: [
                FanCurvePoint(temperature: 45, targetRPM: minimum),
                FanCurvePoint(temperature: 60, targetRPM: minimum + Int(Double(range) * 0.35)),
                FanCurvePoint(temperature: 75, targetRPM: minimum + Int(Double(range) * 0.65)),
                FanCurvePoint(temperature: 90, targetRPM: maximum)
            ],
            source: .hottestProcessor
        )
    }
}

enum ControlStatus: Equatable, Sendable {
    case demo
    case monitoring
    case active
    case disabled
    case unavailable
    case error(String)

    var displayName: String {
        switch self {
        case .demo: "Demo mode"
        case .monitoring: "Monitoring active"
        case .active: "Control active"
        case .disabled: "Control disabled"
        case .unavailable: "Control unavailable"
        case .error(let message): message
        }
    }
}

struct HardwareCapabilities: Sendable {
    let canReadSensors: Bool
    let canControlFans: Bool
    let isSimulated: Bool
    let message: String
}

enum HardwareServiceError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidCommand(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidCommand(let message): message
        }
    }
}
