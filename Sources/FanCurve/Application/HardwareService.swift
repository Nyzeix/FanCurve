import Foundation

protocol HardwareService: Sendable {
    func capabilities() async -> HardwareCapabilities
    func snapshot() async throws -> SystemSnapshot
    func setTargetRPM(_ rpm: Int, for fanID: FanIdentifier) async throws
    func restoreAutomaticControl() async throws
}

/// Point d’entrée unique pour le backend matériel.
///
/// Le backend réel AppleSMC devra être branché ici, derrière cette abstraction,
/// avec un helper privilégié et un test de compatibilité par modèle/macOS.
enum HardwareServiceFactory {
    static func makeDefault() -> any HardwareService {
        #if os(macOS)
        if let service = try? AppleSMCHardwareService() {
            return PrivilegedHardwareService(reader: service)
        }
        #endif

        // Le mode démonstration reste le repli sûr si AppleSMC est absent,
        // inaccessible ou incompatible avec la version de macOS.
        return SimulatedHardwareService()
    }
}
