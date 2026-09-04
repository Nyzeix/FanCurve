import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class FanControlViewModel: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty
    @Published var curve: FanCurve
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

    private let hardwareService: any HardwareService
    private let curveValidator = FanCurveValidator()
    private let curveCalculator = FanCurveCalculator()
    private var monitoringTask: Task<Void, Never>?
    private var savedCurve: FanCurve

    init(hardwareService: any HardwareService = HardwareServiceFactory.makeDefault()) {
        self.hardwareService = hardwareService
        let defaultCurve = FanCurve.recommended(limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_000))
        let storedCurve = Self.loadCurve() ?? defaultCurve
        curve = storedCurve
        menuBarPreferences = Self.loadMenuBarPreferences()
        savedCurve = storedCurve
    }

    deinit {
        monitoringTask?.cancel()
    }

    var fanLimits: FanLimits {
        snapshot.fans.first?.limits ?? FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)
    }

    var maximumTemperature: Double? {
        snapshot.referenceTemperature
    }

    var totalFanRPM: Int {
        snapshot.fans.map(\.currentRPM).reduce(0, +)
    }

    func start() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCapabilities()

            while !Task.isCancelled {
                await self.refreshSnapshot()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        Task { [hardwareService] in
            try? await hardwareService.restoreAutomaticControl()
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
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        menuBarPreferences.displayMode = mode
        saveMenuBarPreferences()
    }

    func setTemperatureUnit(_ unit: TemperatureUnit) {
        menuBarPreferences.temperatureUnit = unit
        saveMenuBarPreferences()
    }

    func installHelper() {
        do {
            try SMAppService.daemon(plistName: "com.paink.FanCurve.helper.plist").register()
            errorMessage = nil
            Task { await refreshCapabilities() }
        } catch {
            errorMessage = "Automatic installation is unavailable for this local build. Run Scripts/install-helper.sh with administrator privileges, then relaunch FanCurve."
        }
    }

    func saveCurve() {
        do {
            try curveValidator.validate(curve, limits: fanLimits)
            Self.saveCurve(curve)
            savedCurve = curve
            errorMessage = nil

            if isControlEnabled {
                Task { await applyCurrentCurve() }
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
            status = .unavailable
            return
        }

        do {
            try curveValidator.validate(curve, limits: fanLimits)
            isControlEnabled = true
            status = .active
            errorMessage = nil
            Task { await applyCurrentCurve() }
        } catch {
            errorMessage = error.localizedDescription
            status = .error(error.localizedDescription)
        }
    }

    private func disableControl() {
        isControlEnabled = false
        status = snapshot.isSimulated ? .demo : .monitoring

        Task { [hardwareService] in
            try? await hardwareService.restoreAutomaticControl()
        }
    }

    private func refreshCapabilities() async {
        capabilities = await hardwareService.capabilities()
        if capabilities.isSimulated {
            status = .demo
        } else if !capabilities.canControlFans {
            status = .unavailable
        } else {
            status = .monitoring
        }
    }

    private func refreshSnapshot() async {
        do {
            let newSnapshot = try await hardwareService.snapshot()
            snapshot = newSnapshot

            if isControlEnabled {
                await applyCurrentCurve()
            } else if newSnapshot.isSimulated {
                status = .demo
            }
        } catch {
            errorMessage = error.localizedDescription
            status = .error("Unable to read sensors")
            await restoreAutomaticControl()
        }
    }

    private func applyCurrentCurve() async {
        guard isControlEnabled, let temperature = referenceTemperature else { return }

        do {
            try curveValidator.validate(curve, limits: fanLimits)
            for fan in snapshot.fans {
                let targetRPM = curveCalculator.targetRPM(
                    for: temperature,
                    curve: curve,
                    limits: fan.limits
                )
                try await hardwareService.setTargetRPM(targetRPM, for: fan.id)
            }
            status = .active
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await restoreAutomaticControl()
        }
    }

    private var referenceTemperature: Double? {
        switch curve.source {
        case .hottestProcessor: snapshot.referenceTemperature
        case .cpu: snapshot.cpuTemperature
        case .gpu: snapshot.gpuTemperature
        }
    }

    private func restoreAutomaticControl() async {
        isControlEnabled = false
        status = snapshot.isSimulated ? .demo : .monitoring
        try? await hardwareService.restoreAutomaticControl()
    }

    private static func loadCurve() -> FanCurve? {
        guard let data = UserDefaults.standard.data(forKey: "FanCurve.savedCurve") else { return nil }
        return try? JSONDecoder().decode(FanCurve.self, from: data)
    }

    private static func saveCurve(_ curve: FanCurve) {
        guard let data = try? JSONEncoder().encode(curve) else { return }
        UserDefaults.standard.set(data, forKey: "FanCurve.savedCurve")
    }

    private func saveMenuBarPreferences() {
        guard let data = try? JSONEncoder().encode(menuBarPreferences) else { return }
        UserDefaults.standard.set(data, forKey: "FanCurve.menuBarPreferences")
    }

    private static func loadMenuBarPreferences() -> MenuBarPreferences {
        guard let data = UserDefaults.standard.data(forKey: "FanCurve.menuBarPreferences") else {
            return MenuBarPreferences()
        }
        return (try? JSONDecoder().decode(MenuBarPreferences.self, from: data)) ?? MenuBarPreferences()
    }

}
