import Foundation

enum FanCurveValidationError: LocalizedError, Equatable, Sendable {
    case tooFewPoints
    case temperatureOutOfBounds
    case temperaturesNotIncreasing
    case speedOutOfBounds
    case speedDecreases
    case invalidNumber

    var errorDescription: String? {
        switch self {
        case .tooFewPoints: "The curve must contain at least two points."
        case .temperatureOutOfBounds: "Temperature must be between 35 °C and 105 °C."
        case .temperaturesNotIncreasing: "Temperatures must be strictly increasing."
        case .speedOutOfBounds: "A fan speed is outside the fan limits."
        case .speedDecreases: "Fan speed cannot decrease as temperature increases."
        case .invalidNumber: "The curve contains an invalid value."
        }
    }
}

struct FanCurveValidator: Sendable {
    func validate(_ curve: FanCurve, limits: FanLimits) throws {
        guard curve.points.count >= 2 else {
            throw FanCurveValidationError.tooFewPoints
        }

        for point in curve.points {
            guard point.temperature.isFinite,
                  point.temperature >= FanCurveTemperatureLimits.minimum,
                  point.temperature <= FanCurveTemperatureLimits.maximum else {
                throw FanCurveValidationError.temperatureOutOfBounds
            }

            let isZeroRPM = point.targetRPM == 0
            let isWithinHardwareRange = point.targetRPM >= limits.minimumRPM
                && point.targetRPM <= limits.maximumRPM
            guard isZeroRPM || isWithinHardwareRange else {
                throw FanCurveValidationError.speedOutOfBounds
            }
        }

        for pair in zip(curve.points, curve.points.dropFirst()) {
            guard pair.1.temperature.isFinite, pair.1.temperature > pair.0.temperature else {
                throw FanCurveValidationError.temperaturesNotIncreasing
            }
            guard pair.1.targetRPM >= pair.0.targetRPM else {
                throw FanCurveValidationError.speedDecreases
            }
        }
    }
}

struct FanCurveCalculator: Sendable {
    func targetRPM(for temperature: Double, curve: FanCurve, limits: FanLimits) -> Int {
        guard let first = curve.points.first else { return limits.minimumRPM }
        guard let last = curve.points.last else { return limits.minimumRPM }

        if temperature <= first.temperature {
            return first.targetRPM.clampedForFan(limits: limits)
        }
        if temperature >= last.temperature {
            return last.targetRPM.clampedForFan(limits: limits)
        }

        for pair in zip(curve.points, curve.points.dropFirst()) {
            let lower = pair.0
            let upper = pair.1
            guard temperature <= upper.temperature else { continue }

            let temperatureRange = upper.temperature - lower.temperature
            let progress = (temperature - lower.temperature) / temperatureRange
            let speed = Double(lower.targetRPM) + progress * Double(upper.targetRPM - lower.targetRPM)
            return Int(speed.rounded()).clampedForFan(limits: limits)
        }

        return last.targetRPM.clampedForFan(limits: limits)
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
