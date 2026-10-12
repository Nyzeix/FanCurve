import Foundation

struct FanCommandPolicy {
    private struct AppliedTarget {
        let rpm: Int
        let appliedAt: ContinuousClock.Instant
    }

    private var appliedTargets: [FanIdentifier: AppliedTarget] = [:]

    func shouldSend(_ rpm: Int, to fanID: FanIdentifier, at now: ContinuousClock.Instant) -> Bool {
        guard let previous = appliedTargets[fanID] else { return true }
        // Changed targets are immediate; unchanged targets are reasserted periodically.
        return previous.rpm != rpm || previous.appliedAt.duration(to: now) >= .seconds(10)
    }

    mutating func record(_ rpm: Int, for fanID: FanIdentifier, at now: ContinuousClock.Instant) {
        appliedTargets[fanID] = AppliedTarget(rpm: rpm, appliedAt: now)
    }

    mutating func reset() {
        appliedTargets.removeAll()
    }
}
