import FanCurveSMC
import FanCurveXPC
import Foundation

private let machServiceName = "com.paink.FanCurve.helper"

final class HelperService: NSObject, FanCurveHelperProtocol {
    private let device: SMCDevice?
    private let initializationError: Error?
    private let lock = NSLock()

    override init() {
        do {
            device = try SMCDevice()
            initializationError = nil
        } catch {
            device = nil
            initializationError = error
        }
        super.init()
    }

    func probe(withReply reply: @escaping (Bool, String) -> Void) {
        guard let device else {
            reply(false, initializationError?.localizedDescription ?? "AppleSMC unavailable.")
            return
        }

        lock.lock()
        let canControl = device.canControlFans()
        lock.unlock()

        if canControl {
            reply(true, "FanCurve helper active.")
        } else {
            reply(false, "AppleSMC control keys are unavailable.")
        }
    }

    func setTargetRPM(_ rpm: Int, fanIndex: Int, withReply reply: @escaping (NSError?) -> Void) {
        guard let device else {
            reply(makeError(initializationError?.localizedDescription ?? "AppleSMC unavailable."))
            return
        }

        do {
            lock.lock()
            defer { lock.unlock() }
            try device.setTargetRPM(rpm, fanIndex: fanIndex)
            reply(nil)
        } catch {
            reply(makeError(error.localizedDescription))
        }
    }

    func restoreAutomaticControl(withReply reply: @escaping (NSError?) -> Void) {
        guard let device else {
            reply(nil)
            return
        }

        do {
            lock.lock()
            defer { lock.unlock() }
            try device.restoreAutomaticControl()
            reply(nil)
        } catch {
            reply(makeError(error.localizedDescription))
        }
    }

    func restoreAfterDisconnect() {
        guard let device else { return }
        lock.lock()
        defer { lock.unlock() }
        try? device.restoreAutomaticControl()
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "FanCurveHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanCurveHelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [service] in
            service.restoreAfterDisconnect()
        }
        newConnection.interruptionHandler = { [service] in
            service.restoreAfterDisconnect()
        }
        newConnection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: machServiceName)
let listenerDelegate = ListenerDelegate()
listener.delegate = listenerDelegate
listener.resume()
RunLoop.current.run()
