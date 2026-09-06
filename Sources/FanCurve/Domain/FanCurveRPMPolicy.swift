enum FanCurveRPMPolicy: Sendable {
    static let minimumNonZeroRPM = 2_350

    static func minimumNonZeroRPM(for limits: FanLimits) -> Int {
        max(minimumNonZeroRPM, limits.minimumRPM)
    }

    static func isInForbiddenRange(_ rpm: Int) -> Bool {
        rpm > 0 && rpm < minimumNonZeroRPM
    }

    static func isValid(_ rpm: Int, for limits: FanLimits) -> Bool {
        guard rpm == 0 else {
            let minimum = minimumNonZeroRPM(for: limits)
            return minimum <= limits.maximumRPM && minimum...limits.maximumRPM ~= rpm
        }
        return true
    }

    static func clamped(_ rpm: Int, for limits: FanLimits) -> Int {
        guard rpm > 0 else { return 0 }

        let minimum = minimumNonZeroRPM(for: limits)
        guard minimum <= limits.maximumRPM else { return 0 }
        return min(max(rpm, minimum), limits.maximumRPM)
    }
}
