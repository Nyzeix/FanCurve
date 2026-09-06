import Foundation

enum FanCurveValidationError: LocalizedError, Equatable, Sendable {
    case tooFewPoints
    case temperatureOutOfBounds
    case temperaturesNotIncreasing
    case speedOutOfBounds
    case speedInForbiddenRange
    case speedDecreases
    case invalidNumber

    var errorDescription: String? {
        switch self {
        case .tooFewPoints: "The curve must contain at least two points."
        case .temperatureOutOfBounds: "Temperature must be between 35 °C and 105 °C."
        case .temperaturesNotIncreasing: "Temperatures must be strictly increasing."
        case .speedOutOfBounds: "A fan speed is outside the fan limits."
        case .speedInForbiddenRange: "Fan speed must be 0 RPM or at least 2,350 RPM."
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

            guard !FanCurveRPMPolicy.isInForbiddenRange(point.targetRPM) else {
                throw FanCurveValidationError.speedInForbiddenRange
            }
            guard FanCurveRPMPolicy.isValid(point.targetRPM, for: limits) else {
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
            return FanCurveRPMPolicy.clamped(first.targetRPM, for: limits)
        }
        if temperature >= last.temperature {
            return FanCurveRPMPolicy.clamped(last.targetRPM, for: limits)
        }

        for pair in zip(curve.points, curve.points.dropFirst()) {
            let lower = pair.0
            let upper = pair.1
            guard temperature <= upper.temperature else { continue }

            if temperature == upper.temperature {
                return FanCurveRPMPolicy.clamped(upper.targetRPM, for: limits)
            }

            if lower.targetRPM == 0 {
                return 0
            }

            let temperatureRange = upper.temperature - lower.temperature
            let progress = (temperature - lower.temperature) / temperatureRange
            let speed = Double(lower.targetRPM) + progress * Double(upper.targetRPM - lower.targetRPM)
            return FanCurveRPMPolicy.clamped(Int(speed.rounded()), for: limits)
        }

        return FanCurveRPMPolicy.clamped(last.targetRPM, for: limits)
    }
}
