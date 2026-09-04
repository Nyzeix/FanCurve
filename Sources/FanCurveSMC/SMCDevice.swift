#if os(macOS)

import Foundation
import IOKit

public struct SMCFanReading: Sendable {
    public let index: Int
    public let currentRPM: Int
    public let targetRPM: Int?
    public let minimumRPM: Int
    public let maximumRPM: Int

    public init(index: Int, currentRPM: Int, targetRPM: Int?, minimumRPM: Int, maximumRPM: Int) {
        self.index = index
        self.currentRPM = currentRPM
        self.targetRPM = targetRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

public struct SMCTemperatureReadings: Sendable {
    public let cpu: Double?
    public let gpu: Double?
    public let battery: Double?

    public init(cpu: Double?, gpu: Double?, battery: Double?) {
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
    }
}

public enum SMCDeviceError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidKey
    case invalidFan
    case invalidSpeed
    case firmwareRejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .firmwareRejected(let message): message
        case .invalidKey: "Invalid AppleSMC key."
        case .invalidFan: "Invalid fan."
        case .invalidSpeed: "Fan speed is out of range."
        }
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuLimit: UInt32 = 0
    var gpuLimit: UInt32 = 0
    var memoryLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var attributes: UInt8 = 0
}

private struct SMCParameter {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private struct SMCValue: Sendable {
    let bytes: [UInt8]
    let dataType: String
}

private final class SMCConnection: @unchecked Sendable {
    private let connection: io_connect_t

    init() throws {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        )
        guard result == kIOReturnSuccess else {
            throw SMCDeviceError.unavailable("The AppleSMC controller is inaccessible.")
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw SMCDeviceError.unavailable("The AppleSMC controller is unavailable.")
        }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
        guard openResult == kIOReturnSuccess else {
            throw SMCDeviceError.unavailable("Connection to the AppleSMC controller failed.")
        }
        connection = openedConnection
    }

    deinit {
        IOServiceClose(connection)
    }

    func read(_ key: String) throws -> SMCValue {
        let keyInfo = try readKeyInfo(for: key)
        var request = SMCParameter()
        request.key = try fourCharacterCode(from: key)
        request.keyInfo.dataSize = keyInfo.info.dataSize
        request.data8 = SMCCommand.readBytes.rawValue

        let response = try call(request)
        guard response.result == 0 else {
            throw SMCDeviceError.firmwareRejected("Reading key \(key) was rejected.")
        }

        let bytes = withUnsafeBytes(of: response.bytes) { buffer in
            Array(buffer.prefix(Int(keyInfo.info.dataSize)))
        }
        return SMCValue(bytes: bytes, dataType: keyInfo.dataType)
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        let keyInfo = try readKeyInfo(for: key)
        guard bytes.count <= Int(keyInfo.info.dataSize) else {
            throw SMCDeviceError.invalidSpeed
        }

        var request = SMCParameter()
        request.key = try fourCharacterCode(from: key)
        request.keyInfo.dataSize = keyInfo.info.dataSize
        request.data8 = SMCCommand.writeBytes.rawValue
        request.bytes = bytesToTuple(bytes, size: Int(keyInfo.info.dataSize))

        let response = try call(request)
        guard response.result == 0 else {
            throw SMCDeviceError.firmwareRejected("The firmware rejected writing \(key).")
        }
    }

    private func readKeyInfo(for key: String) throws -> (info: SMCKeyInfo, dataType: String) {
        var request = SMCParameter()
        request.key = try fourCharacterCode(from: key)
        request.data8 = SMCCommand.readKeyInfo.rawValue
        let response = try call(request)
        guard response.result == 0 else {
            throw SMCDeviceError.unavailable("AppleSMC key \(key) is unavailable.")
        }

        let dataType = withUnsafeBytes(of: response.keyInfo.dataType.bigEndian) { buffer in
            (String(bytes: buffer, encoding: .ascii) ?? "????")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (response.keyInfo, dataType)
    }

    private func call(_ request: SMCParameter) throws -> SMCParameter {
        var input = SMCParameter()
        input.key = request.key
        input.keyInfo.dataSize = request.keyInfo.dataSize
        input.data8 = request.data8
        input.data32 = request.data32
        input.bytes = request.bytes

        var output = SMCParameter()
        var outputSize = MemoryLayout<SMCParameter>.stride
        let result = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCParameter>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw SMCDeviceError.unavailable("IOKit returned code 0x\(String(result, radix: 16)).")
        }
        return output
    }

    private func fourCharacterCode(from value: String) throws -> UInt32 {
        guard value.utf8.count == 4 else { throw SMCDeviceError.invalidKey }
        return fourCharacterCodeUnchecked(value)
    }

    private func fourCharacterCodeUnchecked(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func bytesToTuple(_ bytes: [UInt8], size: Int) -> SMCParameter.Bytes {
        let padded = Array((bytes + Array(repeating: 0, count: max(0, size - bytes.count))).prefix(32))
        let values = padded + Array(repeating: 0, count: max(0, 32 - padded.count))
        return (
            values[0], values[1], values[2], values[3],
            values[4], values[5], values[6], values[7],
            values[8], values[9], values[10], values[11],
            values[12], values[13], values[14], values[15],
            values[16], values[17], values[18], values[19],
            values[20], values[21], values[22], values[23],
            values[24], values[25], values[26], values[27],
            values[28], values[29], values[30], values[31]
        )
    }
}

public final class SMCDevice: @unchecked Sendable {
    private let connection: SMCConnection

    public init() throws {
        connection = try SMCConnection()
    }

    public func readFans() throws -> [SMCFanReading] {
        let count = readInteger(key: "FNum") ?? 0
        let indexes = count > 0 ? Array(0..<min(count, 8)) : Array(0..<4)
        let fans = indexes.compactMap(readFan(index:))
        guard !fans.isEmpty else {
            throw SMCDeviceError.unavailable("No compatible fans were detected.")
        }
        return fans
    }

    public func readTemperatures() -> SMCTemperatureReadings {
        SMCTemperatureReadings(
            cpu: readTemperature(keys: [
                "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
                "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
                "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y", "TC0P"
            ]),
            gpu: readTemperature(keys: [
                "Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g", "TG0P"
            ]),
            battery: readTemperature(keys: ["TB0T", "TB1T", "TB2T", "TB3T"])
        )
    }

    public func canControlFans() -> Bool {
        guard let fan = (try? readFans())?.first,
              (try? connection.read("F\(fan.index)Tg")) != nil else {
            return false
        }
        return modeKey(for: fan.index) != nil
    }

    public func setTargetRPM(_ rpm: Int, fanIndex: Int) throws {
        let fan = try readFans().first { $0.index == fanIndex }
        guard let fan else { throw SMCDeviceError.invalidFan }
        guard rpm == 0 || fan.minimumRPM...fan.maximumRPM ~= rpm else {
            throw SMCDeviceError.invalidSpeed
        }

        try enableManualMode(for: fan.index)

        let targetKey = "F\(fan.index)Tg"
        guard let target = try? connection.read(targetKey) else {
            throw SMCDeviceError.unavailable("The fan target is unavailable.")
        }
        let bytes = encodeRPM(Float(rpm), dataType: target.dataType, size: target.bytes.count)
        try connection.write(targetKey, bytes: bytes)
    }

    public func restoreAutomaticControl() throws {
        let fans = try readFans()
        for fan in fans {
            guard let modeKey = modeKey(for: fan.index) else { continue }
            do {
                try connection.write(modeKey, bytes: [3])
            } catch {
                try connection.write(modeKey, bytes: [0])
            }
        }
        try? connection.write("Ftst", bytes: [0])
    }

    private func readFan(index: Int) -> SMCFanReading? {
        let actualKey = "F\(index)Ac"
        guard let actual = try? connection.read(actualKey),
              let currentRPM = decodeRPM(actual) else {
            return nil
        }

        let minimumRPM = (try? connection.read("F\(index)Mn")).flatMap(decodeRPM) ?? 1_000
        let maximumRPM = (try? connection.read("F\(index)Mx")).flatMap(decodeRPM) ?? 6_000
        let targetRPM = (try? connection.read("F\(index)Tg")).flatMap(decodeRPM).map { Int($0.rounded()) }

        return SMCFanReading(
            index: index,
            currentRPM: Int(currentRPM.rounded()),
            targetRPM: targetRPM,
            minimumRPM: Int(minimumRPM.rounded()),
            maximumRPM: Int(maximumRPM.rounded())
        )
    }

    private func enableManualMode(for fanIndex: Int) throws {
        guard let modeKey = modeKey(for: fanIndex) else {
            throw SMCDeviceError.unavailable("Manual mode is unavailable on this Mac.")
        }

        do {
            try connection.write(modeKey, bytes: [1])
            return
        } catch {
            try connection.write("Ftst", bytes: [1])
            Thread.sleep(forTimeInterval: 0.5)
        }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            do {
                try connection.write(modeKey, bytes: [1])
                return
            } catch {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        throw SMCDeviceError.unavailable("The firmware did not allow manual mode.")
    }

    private func modeKey(for fanIndex: Int) -> String? {
        ["F\(fanIndex)md", "F\(fanIndex)Md"].first { (try? connection.read($0)) != nil }
    }

    private func readInteger(key: String) -> Int? {
        guard let value = try? connection.read(key) else { return nil }
        switch value.dataType {
        case "ui8": return value.bytes.first.map(Int.init)
        case "ui16": return Int(bigEndianUInt16(value.bytes))
        case "ui32": return Int(bigEndianUInt32(value.bytes))
        default: return nil
        }
    }

    private func readTemperature(keys: [String]) -> Double? {
        keys.lazy
            .compactMap { try? self.connection.read($0) }
            .compactMap(decodeTemperature)
            .first(where: { $0.isFinite && (0...150).contains($0) })
    }

    private func decodeRPM(_ value: SMCValue) -> Double? {
        switch value.dataType {
        case "flt": return decodeFloat(value.bytes).map(Double.init)
        case "fpe2": return Double(bigEndianUInt16(value.bytes)) / 4
        default: return nil
        }
    }

    private func decodeTemperature(_ value: SMCValue) -> Double? {
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: bigEndianUInt16(value.bytes))) / 256
        case "flt": return decodeFloat(value.bytes).map(Double.init)
        case "fpe2": return Double(bigEndianUInt16(value.bytes)) / 4
        default: return nil
        }
    }

    private func encodeRPM(_ value: Float, dataType: String, size: Int) -> [UInt8] {
        if dataType == "flt" || size == 4 {
            return withUnsafeBytes(of: value) { Array($0) }
        }

        let raw = UInt16(max(0, min(16_383, Int(value * 4))))
        return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
    }

    private func decodeFloat(_ bytes: [UInt8]) -> Float? {
        guard bytes.count >= 4 else { return nil }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    private func bigEndianUInt16(_ bytes: [UInt8]) -> UInt16 {
        guard bytes.count >= 2 else { return 0 }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    private func bigEndianUInt32(_ bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}

#endif
