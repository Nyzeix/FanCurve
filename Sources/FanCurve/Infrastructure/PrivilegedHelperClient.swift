import FanCurveXPC
import Foundation

private let fanCurveHelperMachService = "com.paink.FanCurve.helper"

final class PrivilegedHelperClient: @unchecked Sendable {
    private let connection: NSXPCConnection

    init() {
        connection = NSXPCConnection(machServiceName: fanCurveHelperMachService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanCurveHelperProtocol.self)
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    func probe() async -> (available: Bool, message: String) {
        await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(returning: (false, error.localizedDescription))
            }
            guard let helper = proxy as? FanCurveHelperProtocol else {
                continuation.resume(returning: (false, "Helper interface unavailable."))
                return
            }
            helper.probe { available, message in
                continuation.resume(returning: (available, message))
            }
        }
    }

    func setTargetRPM(_ rpm: Int, fanIndex: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? FanCurveHelperProtocol else {
                continuation.resume(throwing: HardwareServiceError.unavailable("Helper interface unavailable."))
                return
            }
            helper.setTargetRPM(rpm, fanIndex: fanIndex) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func restoreAutomaticControl() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? FanCurveHelperProtocol else {
                continuation.resume(throwing: HardwareServiceError.unavailable("Helper interface unavailable."))
                return
            }
            helper.restoreAutomaticControl { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
