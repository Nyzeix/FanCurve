import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class FanControlViewModel: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published var curve: FanCurve
    @Published private(set) var profiles: [FanProfile]
    @Published private(set) var activeProfileID: UUID
    @Published var menuBarPreferences: MenuBarPreferences
    @Published private(set) var status: ControlStatus = .demo
    @Published private(set) var isControlEnabled = false
    @Published private(set) var capabilities = HardwareCapabilities(
        canReadSensors: false,
        canControlFans: false,
        isSimulated: false,
        message: "Initializing…"
    )
    @Published private(set) var errorMessage: String?

    let menuBarStatus = MenuBarStatusModel()

    private let hardwareService: any HardwareService
    private let profileStore: FanProfileStore
    private let userDefaults: UserDefaults
    private let curveValidator = FanCurveValidator()
    private let curveCalculator = FanCurveCalculator()
    private var monitoringTask: Task<Void, Never>?
    private var restorationTask: Task<Void, Never>?
    private var lifecycleSubscriptions: Set<AnyCancellable> = []
    private var latestSnapshot = SystemSnapshot.empty
    private var commandPolicy = FanCommandPolicy()
    private var lastMenuBarUpdate: ContinuousClock.Instant?
    private var monitoringStarted = false
    private var hasLoadedCapabilities = false
    private var isDashboardVisible = false
    private var isMenuBarVisible = false
    private var isSuspended = false
    private var displaysAwake = true
    private var snapshotFailed = false
    private var automaticRestorationPending = false
    private var nextRestorationAttempt: ContinuousClock.Instant?
    private var savedCurve: FanCurve

    init(
        hardwareService: any HardwareService = HardwareServiceFactory.makeDefault(),
        userDefaults: UserDefaults = .standard
    ) {
        self.hardwareService = hardwareService
        self.userDefaults = userDefaults
        profileStore = FanProfileStore(userDefaults: userDefaults)
        let defaultLimits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_550)
        let defaultProfiles = FanProfile.defaults(limits: defaultLimits)
        let storage = profileStore.load(
            defaultProfiles: defaultProfiles,
            legacyCurve: Self.loadCurve(userDefaults: userDefaults)
        )
        let activeProfile = storage.profiles.first { $0.id == storage.activeProfileID }
            ?? storage.profiles[0]

        profiles = storage.profiles
        activeProfileID = activeProfile.id
        curve = activeProfile.curve
        menuBarPreferences = Self.loadMenuBarPreferences(userDefaults: userDefaults)
        savedCurve = activeProfile.curve
        profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
        menuBarStatus.update(snapshot: latestSnapshot, preferences: menuBarPreferences)
        observeSystemSleep()
    }

    deinit {
        monitoringTask?.cancel()
    }

    var fanLimits: FanLimits {
        latestSnapshot.fans.first?.limits ?? FanLimits(minimumRPM: 1_000, maximumRPM: 6_550)
    }

    var maximumTemperature: Double? {
        snapshot.referenceTemperature
    }

    var totalFanRPM: Int {
        snapshot.fans.map(\.currentRPM).reduce(0, +)
    }

    var activeProfileName: String {
        profiles.first { $0.id == activeProfileID }?.name ?? "Profile"
    }

    func start() {
        guard !monitoringStarted else { return }
        monitoringStarted = true
        restartMonitoring()
    }

    func stop() async {
        monitoringStarted = false
        disableControl()
        await restorationTask?.value
    }

    func prepareForApplicationUpdate() async -> Bool {
        isControlEnabled = false
        commandPolicy.reset()
        let wasMonitoringStarted = monitoringStarted
        monitoringStarted = false
        defer {
            monitoringStarted = wasMonitoringStarted
            restartMonitoring()
        }
        let previousTask = monitoringTask
        previousTask?.cancel()
        monitoringTask = nil
        await previousTask?.value
        await restorationTask?.value
        setStatus(latestSnapshot.isSimulated ? .demo : .monitoring)

        automaticRestorationPending = true
        if await attemptAutomaticRestoration() {
            return true
        } else {
            errorMessage = "Fan control could not be returned to macOS. The update was cancelled."
            return false
        }
    }

    func setControlEnabled(_ enabled: Bool) {
        if enabled {
            enableControl()
        } else {
            disableControl()
        }
    }

    func setMenuBarUpdateInterval(_ interval: MenuBarUpdateInterval) {
        menuBarPreferences.updateInterval = interval
        saveMenuBarPreferences()
        updateMenuBar(force: true)
        restartMonitoring()
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        menuBarPreferences.displayMode = mode
        saveMenuBarPreferences()
        updateMenuBar(force: true)
        restartMonitoring()
    }

    func setTemperatureUnit(_ unit: TemperatureUnit) {
        menuBarPreferences.temperatureUnit = unit
        saveMenuBarPreferences()
        updateMenuBar(force: true)
    }

    func setDashboardVisible(_ visible: Bool) {
        guard isDashboardVisible != visible else { return }
        isDashboardVisible = visible
        restartMonitoring()
    }

    func setMenuBarVisible(_ visible: Bool) {
        guard isMenuBarVisible != visible else { return }
        isMenuBarVisible = visible
        restartMonitoring()
    }

    private var readingsVisible: Bool {
        displaysAwake && (isDashboardVisible || isMenuBarVisible)
    }

    private func restartMonitoring() {
        guard monitoringStarted else { return }
        let previousTask = monitoringTask
        previousTask?.cancel()
        let pendingRestoration = restorationTask

        monitoringTask = Task { [weak self] in
            // Finish the preceding hardware operation before starting another loop.
            await previousTask?.value
            await pendingRestoration?.value
            guard let self, !Task.isCancelled else { return }
            if !self.hasLoadedCapabilities {
                await self.refreshCapabilities()
                self.hasLoadedCapabilities = true
            }

            while !Task.isCancelled {
                if self.automaticRestorationPending {
                    if let retryAt = self.nextRestorationAttempt, retryAt > ContinuousClock.now {
                        do {
                            try await Task.sleep(until: retryAt, tolerance: .milliseconds(200), clock: .continuous)
                        } catch { return }
                        guard !Task.isCancelled else { return }
                    }
                    guard await self.attemptAutomaticRestoration() else { continue }
                    guard !Task.isCancelled else { return }
                }
                guard let interval = MonitoringPolicy.interval(
                    controlEnabled: self.isControlEnabled,
                    readingsVisible: self.readingsVisible,
                    displayMode: self.menuBarPreferences.displayMode,
                    refreshInterval: self.menuBarPreferences.updateInterval,
                    suspended: self.isSuspended,
                    displayAwake: self.displaysAwake
                ) else { return }

                await self.refreshSnapshot()
                guard !Task.isCancelled else { return }
                do {
                    let delay = self.snapshotFailed ? max(interval, .seconds(5)) : interval
                    try await Task.sleep(for: delay, tolerance: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.suspendForSleep() }
            }
            .store(in: &lifecycleSubscriptions)
        center.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.resumeAfterSleep() }
            }
            .store(in: &lifecycleSubscriptions)
        center.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.setDisplaysAwake(false) }
            }
            .store(in: &lifecycleSubscriptions)
        center.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.setDisplaysAwake(true) }
            }
            .store(in: &lifecycleSubscriptions)
    }

    private func setDisplaysAwake(_ awake: Bool) {
        guard displaysAwake != awake else { return }
        displaysAwake = awake
        restartMonitoring()
    }

    func suspendForSleep() {
        isSuspended = true
        disableControl()
    }

    func resumeAfterSleep() async {
        await hardwareService.invalidateCachedMetadata()
        hasLoadedCapabilities = false
        lastMenuBarUpdate = nil
        isSuspended = false
        displaysAwake = true
        restartMonitoring()
    }

    func selectProfile(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }

        activeProfileID = profile.id
        curve = profile.curve
        savedCurve = profile.curve
        profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
        errorMessage = nil

        if isControlEnabled {
            restartMonitoring()
        }
    }

    func createProfile(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let profile = FanProfile(name: trimmedName, curve: curve)
        profiles.append(profile)
        activeProfileID = profile.id
        savedCurve = profile.curve
        profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
        errorMessage = nil
    }

    func renameActiveProfile(to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }

        profiles[index].name = trimmedName
        profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
    }

    func deleteActiveProfile() {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }

        profiles.remove(at: index)
        let replacementIndex = min(index, profiles.count - 1)
        let replacement = profiles[replacementIndex]
        activeProfileID = replacement.id
        curve = replacement.curve
        savedCurve = replacement.curve
        profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
        errorMessage = nil

        if isControlEnabled {
            restartMonitoring()
        }
    }

    func installHelper() {
        do {
            try SMAppService.daemon(plistName: "FanCurve.helper.plist").register()
            errorMessage = nil
            Task { await refreshCapabilities() }
        } catch {
            errorMessage = "Automatic installation is unavailable for this local build. Run Scripts/install-helper.sh with administrator privileges, then relaunch FanCurve."
        }
    }

    func saveCurve() {
        do {
            try curveValidator.validate(curve, limits: fanLimits)
            if let index = profiles.firstIndex(where: { $0.id == activeProfileID }) {
                profiles[index].curve = curve
            }
            profileStore.save(profiles: profiles, activeProfileID: activeProfileID)
            Self.saveCurve(curve, userDefaults: userDefaults)
            savedCurve = curve
            errorMessage = nil

            if isControlEnabled {
                restartMonitoring()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreSavedCurve() {
        curve = savedCurve
        errorMessage = nil
    }

    func restoreRecommendedCurve() {
        curve = .recommended(limits: fanLimits)
        errorMessage = nil
    }

    func addPoint() {
        guard curve.points.count < 12 else { return }

        let points = curve.points.sorted { $0.temperature < $1.temperature }
        let temperature: Double
        if let first = points.first, let last = points.last {
            temperature = (first.temperature + last.temperature) / 2
        } else {
            temperature = 65
        }

        let interpolatedRPM = curveCalculator.targetRPM(
            for: temperature,
            curve: FanCurve(points: points, source: curve.source),
            limits: fanLimits
        )
        curve.points.append(FanCurvePoint(temperature: temperature, targetRPM: interpolatedRPM))
        curve.points.sort { $0.temperature < $1.temperature }
    }

    func removePoints(at offsets: IndexSet) {
        guard curve.points.count - offsets.count >= 2 else { return }
        curve.points.remove(atOffsets: offsets)
    }

    private func enableControl() {
        guard !isControlEnabled else { return }

        guard capabilities.canControlFans else {
            errorMessage = capabilities.message
            setStatus(.unavailable)
            return
        }

        do {
            try curveValidator.validate(curve, limits: fanLimits)
            isControlEnabled = true
            commandPolicy.reset()
            setStatus(.active)
            clearError()
            restartMonitoring()
        } catch {
            errorMessage = error.localizedDescription
            setStatus(.error(error.localizedDescription))
        }
    }

    private func disableControl() {
        if isControlEnabled { isControlEnabled = false }
        commandPolicy.reset()
        automaticRestorationPending = true
        nextRestorationAttempt = nil
        setStatus(latestSnapshot.isSimulated ? .demo : .monitoring)
        let previousTask = monitoringTask
        previousTask?.cancel()
        monitoringTask = nil
        let previousRestoration = restorationTask
        restorationTask = Task { [weak self] in
            await previousTask?.value
            await previousRestoration?.value
            await self?.attemptAutomaticRestoration()
        }
        restartMonitoring()
    }

    private func refreshCapabilities() async {
        capabilities = await hardwareService.capabilities()
        if capabilities.isSimulated {
            setStatus(.demo)
        } else if !capabilities.canControlFans {
            setStatus(.unavailable)
        } else {
            setStatus(.monitoring)
        }
    }

    private func refreshSnapshot() async {
        do {
            let newSnapshot = try await hardwareService.snapshot()
            guard !Task.isCancelled, !isSuspended else { return }
            snapshotFailed = false
            latestSnapshot = newSnapshot
            if readingsVisible && !newSnapshot.hasSameDisplayedReadings(
                as: snapshot,
                unit: menuBarPreferences.temperatureUnit
            ) {
                snapshot = newSnapshot
            }
            updateMenuBar()

            if isControlEnabled {
                await applyCurrentCurve()
            } else {
                setStatus(newSnapshot.isSimulated ? .demo : (capabilities.canControlFans ? .monitoring : .unavailable))
            }
        } catch {
            guard !Task.isCancelled else { return }
            snapshotFailed = true
            if errorMessage != error.localizedDescription {
                errorMessage = error.localizedDescription
            }
            if isControlEnabled || automaticRestorationPending {
                await restoreAutomaticControl()
            }
            setStatus(.error("Unable to read sensors"))
        }
    }

    private func applyCurrentCurve() async {
        guard isControlEnabled else { return }
        guard let temperature = referenceTemperature, temperature.isFinite else {
            errorMessage = "The temperature required by the curve is unavailable."
            await restoreAutomaticControl()
            setStatus(.error("Unable to read sensors"))
            return
        }

        do {
            try curveValidator.validate(curve, limits: fanLimits)
            for fan in latestSnapshot.fans {
                guard isControlEnabled, !Task.isCancelled, !isSuspended else { return }
                let targetRPM = curveCalculator.targetRPM(
                    for: temperature,
                    curve: curve,
                    limits: fan.limits
                )
                let now = ContinuousClock.now
                if commandPolicy.shouldSend(targetRPM, to: fan.id, at: now) {
                    try await hardwareService.setTargetRPM(targetRPM, for: fan.id)
                    guard isControlEnabled, !Task.isCancelled, !isSuspended else { return }
                    commandPolicy.record(targetRPM, for: fan.id, at: .now)
                }
            }
            guard isControlEnabled, !Task.isCancelled else { return }
            setStatus(.active)
            clearError()
        } catch {
            errorMessage = error.localizedDescription
            await restoreAutomaticControl()
        }
    }

    private var referenceTemperature: Double? {
        switch curve.source {
        case .hottestProcessor: latestSnapshot.referenceTemperature
        case .cpu: latestSnapshot.cpuTemperature
        case .gpu: latestSnapshot.gpuTemperature
        }
    }

    private func restoreAutomaticControl() async {
        isControlEnabled = false
        commandPolicy.reset()
        automaticRestorationPending = true
        setStatus(latestSnapshot.isSimulated ? .demo : .monitoring)
        await attemptAutomaticRestoration()
    }

    @discardableResult
    private func attemptAutomaticRestoration() async -> Bool {
        do {
            try await hardwareService.restoreAutomaticControl()
            automaticRestorationPending = false
            nextRestorationAttempt = nil
            commandPolicy.reset()
            return true
        } catch {
            automaticRestorationPending = true
            nextRestorationAttempt = ContinuousClock.now.advanced(by: .seconds(5))
            let message = "Fan control could not be returned to macOS: \(error.localizedDescription)"
            if errorMessage != message { errorMessage = message }
            setStatus(.error("Waiting to restore macOS control"))
            return false
        }
    }

    private func updateMenuBar(force: Bool = false) {
        guard displaysAwake || force else { return }
        let now = ContinuousClock.now
        if !force, let lastMenuBarUpdate,
           lastMenuBarUpdate.duration(to: now) < menuBarPreferences.updateInterval.duration {
            return
        }
        menuBarStatus.update(snapshot: latestSnapshot, preferences: menuBarPreferences)
        lastMenuBarUpdate = now
    }

    private func setStatus(_ next: ControlStatus) {
        if status != next { status = next }
    }

    private func clearError() {
        if errorMessage != nil { errorMessage = nil }
    }

    private static func loadCurve(userDefaults: UserDefaults) -> FanCurve? {
        guard let data = userDefaults.data(forKey: "FanCurve.savedCurve") else { return nil }
        return try? JSONDecoder().decode(FanCurve.self, from: data)
    }

    private static func saveCurve(_ curve: FanCurve, userDefaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(curve) else { return }
        userDefaults.set(data, forKey: "FanCurve.savedCurve")
    }

    private func saveMenuBarPreferences() {
        guard let data = try? JSONEncoder().encode(menuBarPreferences) else { return }
        userDefaults.set(data, forKey: "FanCurve.menuBarPreferences")
    }

    private static func loadMenuBarPreferences(userDefaults: UserDefaults) -> MenuBarPreferences {
        guard let data = userDefaults.data(forKey: "FanCurve.menuBarPreferences") else {
            return MenuBarPreferences()
        }
        return (try? JSONDecoder().decode(MenuBarPreferences.self, from: data)) ?? MenuBarPreferences()
    }

}
