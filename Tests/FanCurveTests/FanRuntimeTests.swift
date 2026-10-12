import Combine
import XCTest
@testable import FanCurve

final class FanRuntimeTests: XCTestCase {
    func testMonitoringPolicyPausesUnusedSensorsAndKeepsControlResponsive() {
        XCTAssertNil(MonitoringPolicy.interval(
            controlEnabled: false, readingsVisible: false, displayMode: .temperatureIcon,
            refreshInterval: .oneSecond, suspended: false
        ))
        XCTAssertEqual(MonitoringPolicy.interval(
            controlEnabled: false, readingsVisible: false, displayMode: .temperatureAndRPM,
            refreshInterval: .tenSeconds, suspended: false
        ), .seconds(10))
        for controlEnabled in [false, true] {
            XCTAssertEqual(MonitoringPolicy.interval(
                controlEnabled: controlEnabled, readingsVisible: true, displayMode: .temperatureIcon,
                refreshInterval: .tenSeconds, suspended: false
            ), .seconds(1))
        }
        XCTAssertEqual(MonitoringPolicy.interval(
            controlEnabled: true, readingsVisible: false, displayMode: .temperatureIcon,
            refreshInterval: .tenSeconds, suspended: false
        ), .seconds(1))
        XCTAssertNil(MonitoringPolicy.interval(
            controlEnabled: true, readingsVisible: true, displayMode: .temperatureAndRPM,
            refreshInterval: .oneSecond, suspended: true
        ))
        XCTAssertNil(MonitoringPolicy.interval(
            controlEnabled: false, readingsVisible: true, displayMode: .temperatureAndRPM,
            refreshInterval: .oneSecond, suspended: false, displayAwake: false
        ))
        XCTAssertEqual(MonitoringPolicy.interval(
            controlEnabled: true, readingsVisible: false, displayMode: .temperatureIcon,
            refreshInterval: .oneSecond, suspended: false, displayAwake: false
        ), .seconds(1))
    }

    func testUnchangedTargetsAreSuppressedWithPeriodicRevalidation() {
        let fan = FanIdentifier(rawValue: "fan-0")
        var policy = FanCommandPolicy()
        let start = ContinuousClock.now
        XCTAssertTrue(policy.shouldSend(2_350, to: fan, at: start))
        policy.record(2_350, for: fan, at: start)
        XCTAssertFalse(policy.shouldSend(2_350, to: fan, at: start.advanced(by: .seconds(9))))
        XCTAssertTrue(policy.shouldSend(2_350, to: fan, at: start.advanced(by: .seconds(10))))
        XCTAssertTrue(policy.shouldSend(2_351, to: fan, at: start))
        XCTAssertTrue(policy.shouldSend(0, to: fan, at: start))
        XCTAssertTrue(policy.shouldSend(6_550, to: fan, at: start))
        XCTAssertTrue(policy.shouldSend(2_350, to: FanIdentifier(rawValue: "fan-1"), at: start))
        policy.reset()
        XCTAssertTrue(policy.shouldSend(2_350, to: fan, at: start))
    }

    func testDisplayComparisonIgnoresTimestampsAndUsesSelectedUnit() {
        let earlier = sample(temperature: 40.2)
        let later = sample(temperature: 40.4)
        XCTAssertTrue(earlier.hasSameDisplayedReadings(as: later, unit: .celsius))
        XCTAssertFalse(earlier.hasSameDisplayedReadings(as: later, unit: .fahrenheit))
        XCTAssertFalse(earlier.hasSameDisplayedReadings(as: sample(temperature: nil), unit: .celsius))
    }

    @MainActor
    func testMenuBarPublishesOnlyChangedVisibleText() {
        let status = MenuBarStatusModel()
        var updates = 0
        let subscription = status.objectWillChange.sink { updates += 1 }
        status.update(snapshot: sample(temperature: 40.2), preferences: MenuBarPreferences())
        status.update(snapshot: sample(temperature: 40.4), preferences: MenuBarPreferences())
        XCTAssertEqual(updates, 1)
        status.update(snapshot: sample(temperature: 40.4), preferences: MenuBarPreferences(displayMode: .temperatureIcon))
        status.update(snapshot: sample(temperature: 60), preferences: MenuBarPreferences(displayMode: .temperatureIcon))
        XCTAssertEqual(updates, 2)
        XCTAssertEqual(status.presentation.text, "FanCurve")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testIconOnlyBackgroundDoesNotReadSensorsAndOpeningMenuRefreshes() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 50.1))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarDisplayMode(.temperatureIcon)
        model.start()
        try await waitUntil { model.capabilities.canReadSensors }
        let initialReads = await hardware.readCount
        XCTAssertEqual(initialReads, 0)
        model.setMenuBarVisible(true)
        try await waitUntil { await hardware.readCount > 0 }
        XCTAssertEqual(model.snapshot.cpuTemperature, 50.1)
        model.setMenuBarVisible(false)
        await stop(model)
    }

    @MainActor
    func testControlUsesRawTemperaturesEvenWhenDisplayedReadingsMatch() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 50.1))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.curve = FanCurve(points: [
            FanCurvePoint(temperature: 50, targetRPM: 2_350),
            FanCurvePoint(temperature: 70, targetRPM: 4_350)
        ], source: .cpu)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        model.setControlEnabled(true)
        try await waitUntil { await hardware.targets.contains(2_360) }
        await hardware.setSnapshot(sample(temperature: 50.3))
        model.setDashboardVisible(true)
        try await waitUntil { await hardware.targets.contains(2_380) }
        XCTAssertEqual(model.snapshot.cpuTemperature, 50.1)
        await stop(model)
    }

    @MainActor
    func testDisableRestoresAutomaticModeAfterInflightWrite() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 60))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        await hardware.blockNextWrite()
        model.setControlEnabled(true)
        try await waitUntil { await hardware.writeIsBlocked }
        model.setControlEnabled(false)
        try await Task.sleep(for: .milliseconds(30))
        let beforeRelease = await hardware.events
        XCTAssertFalse(beforeRelease.contains("restore"))
        await hardware.releaseWrite()
        try await waitUntil { await hardware.events.contains("restore") }
        let events = await hardware.events
        XCTAssertEqual(events.suffix(2), ["write", "restore"])
        await stop(model)
    }

    @MainActor
    func testMissingControlTemperatureReturnsToAutomaticMode() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: nil))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans }
        model.setControlEnabled(true)
        try await waitUntil { await hardware.events.contains("restore") }
        XCTAssertFalse(model.isControlEnabled)
        let targets = await hardware.targets
        XCTAssertTrue(targets.isEmpty)
        await stop(model)
    }

    @MainActor
    func testSleepRestoresControlAndWakeInvalidatesMetadata() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 60))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        model.setControlEnabled(true)
        try await waitUntil { await !hardware.targets.isEmpty }
        model.suspendForSleep()
        try await waitUntil { await hardware.events.contains("restore") }
        XCTAssertFalse(model.isControlEnabled)
        await model.resumeAfterSleep()
        let resets = await hardware.cacheResets
        XCTAssertEqual(resets, 1)
        XCTAssertFalse(model.isControlEnabled)
        await stop(model)
    }

    @MainActor
    func testUpdatePreparationKeepsMonitoringAvailable() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 60))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { await hardware.readCount > 0 }
        let before = await hardware.readCount
        let ready = await model.prepareForApplicationUpdate()
        XCTAssertTrue(ready)
        try await waitUntil { await hardware.readCount > before }
        XCTAssertFalse(model.isControlEnabled)
        await stop(model)
    }

    @MainActor
    func testReadFailureDisablesControlAndRestoresAutomaticMode() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 60))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        model.setControlEnabled(true)
        try await waitUntil { await !hardware.targets.isEmpty }
        await hardware.failReads()
        model.setDashboardVisible(true)
        try await waitUntil { await hardware.events.contains("restore") }
        XCTAssertFalse(model.isControlEnabled)
        XCTAssertNotNil(model.errorMessage)
        await stop(model)
    }

    @MainActor
    func testRapidOffOnReappliesTargetAfterInflightWriteAndRestoration() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 60))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        await hardware.blockNextWrite()
        model.setControlEnabled(true)
        try await waitUntil { await hardware.writeIsBlocked }
        model.setControlEnabled(false)
        model.setControlEnabled(true)
        await hardware.releaseWrite()
        try await waitUntil { await hardware.targets.count == 2 }
        let events = await hardware.events
        XCTAssertEqual(events, ["write", "restore", "write"])
        XCTAssertTrue(model.isControlEnabled)
        await stop(model)
    }

    @MainActor
    func testFailedSafetyRestorationRetriesWithIconOnlyBackground() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hardware = RuntimeHardware(snapshot: sample(temperature: 40))
        let model = FanControlViewModel(hardwareService: hardware, userDefaults: defaults)
        model.setMenuBarDisplayMode(.temperatureIcon)
        model.setMenuBarVisible(true)
        model.start()
        try await waitUntil { model.capabilities.canControlFans && model.snapshot.cpuTemperature != nil }
        model.setControlEnabled(true)
        try await waitUntil { await hardware.targets.contains(0) }
        await hardware.failNextRestoration()
        await hardware.failReads()
        model.setMenuBarVisible(false)
        try await waitUntil { await hardware.events.contains("restoreFailed") }
        XCTAssertFalse(model.isControlEnabled)
        try await waitUntil(timeout: .seconds(7)) { await hardware.events.contains("restore") }
        await stop(model)
    }

    @MainActor
    private func stop(_ model: FanControlViewModel) async {
        await model.stop()
    }

    @MainActor
    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for runtime state")
                throw RuntimeTestError.timeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "FanCurveTests.runtime.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    private func sample(temperature: Double?) -> SystemSnapshot {
        SystemSnapshot(
            capturedAt: .now, cpuTemperature: temperature, gpuTemperature: temperature,
            batteryTemperature: 30,
            fans: [FanSnapshot(id: FanIdentifier(rawValue: "fan-0"), name: "Fan", currentRPM: 2_350,
                               limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550))],
            thermalCondition: .nominal, isSimulated: false
        )
    }
}

private enum RuntimeTestError: Error { case timeout }

private actor RuntimeHardware: HardwareService {
    private var currentSnapshot: SystemSnapshot
    private var blocksNextWrite = false
    private var readsFail = false
    private var restorationFails = false
    private var pendingWrite: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0
    private(set) var cacheResets = 0
    private(set) var targets: [Int] = []
    private(set) var events: [String] = []
    var writeIsBlocked: Bool { pendingWrite != nil }

    init(snapshot: SystemSnapshot) { currentSnapshot = snapshot }

    func capabilities() async -> HardwareCapabilities {
        HardwareCapabilities(canReadSensors: true, canControlFans: true, isSimulated: false, message: "Test backend")
    }

    func snapshot() async throws -> SystemSnapshot {
        readCount += 1
        if readsFail { throw HardwareServiceError.unavailable("Test read failure") }
        return currentSnapshot
    }

    func setSnapshot(_ snapshot: SystemSnapshot) { currentSnapshot = snapshot }
    func failReads() { readsFail = true }
    func failNextRestoration() { restorationFails = true }
    func blockNextWrite() { blocksNextWrite = true }
    func releaseWrite() {
        pendingWrite?.resume()
        pendingWrite = nil
    }

    func setTargetRPM(_ rpm: Int, for fanID: FanIdentifier) async throws {
        if blocksNextWrite {
            blocksNextWrite = false
            await withCheckedContinuation { pendingWrite = $0 }
        }
        targets.append(rpm)
        events.append("write")
    }

    func restoreAutomaticControl() async throws {
        if restorationFails {
            restorationFails = false
            events.append("restoreFailed")
            throw HardwareServiceError.unavailable("Test restoration failure")
        }
        events.append("restore")
    }
    func invalidateCachedMetadata() async { cacheResets += 1 }
}
