import Foundation

actor PrivilegedHardwareService: HardwareService {
    private let reader: AppleSMCHardwareService
    private let helper: PrivilegedHelperClient

    init(reader: AppleSMCHardwareService, helper: PrivilegedHelperClient = PrivilegedHelperClient()) {
        self.reader = reader
        self.helper = helper
    }

    func capabilities() async -> HardwareCapabilities {
        let helperStatus = await helper.probe()
        return HardwareCapabilities(
            canReadSensors: true,
            canControlFans: helperStatus.available,
            isSimulated: false,
            message: helperStatus.available
                ? "AppleSMC control available through the privileged helper."
                : "Helper unavailable. Run Scripts/install-helper.sh, then relaunch FanCurve."
        )
    }

    func snapshot() async throws -> SystemSnapshot {
        try await reader.snapshot()
    }

    func setTargetRPM(_ rpm: Int, for fanID: FanIdentifier) async throws {
        guard let fanIndex = Int(fanID.rawValue.replacingOccurrences(of: "fan-", with: "")) else {
            throw HardwareServiceError.invalidCommand("Invalid fan identifier.")
        }
        try await helper.setTargetRPM(rpm, fanIndex: fanIndex)
    }

    func restoreAutomaticControl() async throws {
        try await helper.restoreAutomaticControl()
    }
}
