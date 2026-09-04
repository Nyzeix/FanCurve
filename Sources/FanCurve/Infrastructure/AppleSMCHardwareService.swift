import FanCurveSMC
import Foundation

actor AppleSMCHardwareService: HardwareService {
    private let device: SMCDevice

    init() throws {
        device = try SMCDevice()
    }

    func capabilities() async -> HardwareCapabilities {
        HardwareCapabilities(
            canReadSensors: true,
            canControlFans: false,
            isSimulated: false,
            message: "AppleSMC sensors active. The privileged helper is required to write fan commands."
        )
    }

    func snapshot() async throws -> SystemSnapshot {
        let readings = try device.readFans()
        let temperatures = device.readTemperatures()

        let fans = readings.map { reading in
            FanSnapshot(
                id: FanIdentifier(rawValue: "fan-\(reading.index)"),
                name: reading.index == 0 ? "Left fan" : "Right fan",
                currentRPM: reading.currentRPM,
                limits: FanLimits(minimumRPM: reading.minimumRPM, maximumRPM: reading.maximumRPM)
            )
        }

        return SystemSnapshot(
            capturedAt: .now,
            cpuTemperature: temperatures.cpu,
            gpuTemperature: temperatures.gpu,
            batteryTemperature: temperatures.battery,
            fans: fans,
            thermalCondition: thermalCondition,
            isSimulated: false
        )
    }

    func setTargetRPM(_ rpm: Int, for fanID: FanIdentifier) async throws {
        throw HardwareServiceError.unavailable(
            "The privileged helper is not connected: no command was written."
        )
    }

    func restoreAutomaticControl() async throws {
        // La lecture seule ne modifie aucun état matériel.
    }

    private var thermalCondition: ThermalCondition {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}
