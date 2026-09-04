import Foundation

actor SimulatedHardwareService: HardwareService {
    private let leftFan = FanIdentifier(rawValue: "left")
    private let rightFan = FanIdentifier(rawValue: "right")
    private let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)
    private var targetRPMByFan: [FanIdentifier: Int]
    private var isCustomControlEnabled = false

    init() {
        targetRPMByFan = [
            FanIdentifier(rawValue: "left"): 1_200,
            FanIdentifier(rawValue: "right"): 1_200
        ]
    }

    func capabilities() async -> HardwareCapabilities {
        HardwareCapabilities(
            canReadSensors: true,
            canControlFans: true,
            isSimulated: true,
            message: "Demo mode: no hardware command is sent."
        )
    }

    func snapshot() async throws -> SystemSnapshot {
        let phase = Date.now.timeIntervalSinceReferenceDate
        let cpuTemperature = 54 + 12 * sin(phase / 11)
        let gpuTemperature = 49 + 15 * sin(phase / 17 + 0.8)
        let batteryTemperature = 32 + 2 * sin(phase / 23)
        let hottestTemperature = max(cpuTemperature, gpuTemperature)

        if !isCustomControlEnabled {
            let automaticRPM = hottestTemperature < 55
                ? 0
                : 1_100 + Int(max(0, hottestTemperature - 55) * 42)
            targetRPMByFan[leftFan] = automaticRPM.clampedForFan(limits: limits)
            targetRPMByFan[rightFan] = automaticRPM.clampedForFan(limits: limits)
        }

        let fans = [
            FanSnapshot(
                id: leftFan,
                name: "Left fan",
                currentRPM: targetRPMByFan[leftFan, default: limits.minimumRPM],
                limits: limits
            ),
            FanSnapshot(
                id: rightFan,
                name: "Right fan",
                currentRPM: targetRPMByFan[rightFan, default: limits.minimumRPM],
                limits: limits
            )
        ]

        let thermalCondition: ThermalCondition
        switch hottestTemperature {
        case ..<65: thermalCondition = .nominal
        case ..<80: thermalCondition = .fair
        case ..<95: thermalCondition = .serious
        default: thermalCondition = .critical
        }

        return SystemSnapshot(
            capturedAt: .now,
            cpuTemperature: cpuTemperature,
            gpuTemperature: gpuTemperature,
            batteryTemperature: batteryTemperature,
            fans: fans,
            thermalCondition: thermalCondition,
            isSimulated: true
        )
    }

    func setTargetRPM(_ rpm: Int, for fanID: FanIdentifier) async throws {
        guard targetRPMByFan[fanID] != nil else {
            throw HardwareServiceError.unavailable("Unknown fan.")
        }
        guard rpm == 0 || limits.minimumRPM...limits.maximumRPM ~= rpm else {
            throw HardwareServiceError.invalidCommand("Requested fan speed is out of range.")
        }

        isCustomControlEnabled = true
        targetRPMByFan[fanID] = rpm
    }

    func restoreAutomaticControl() async throws {
        isCustomControlEnabled = false
    }
}

private extension Int {
    func clampedForFan(limits: FanLimits) -> Int {
        if self <= 0 { return 0 }
        return clamped(to: limits.minimumRPM...limits.maximumRPM)
    }

    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
