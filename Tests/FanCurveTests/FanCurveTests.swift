import XCTest
import FanCurveSMC
@testable import FanCurve

final class FanCurveTests: XCTestCase {
    func testAppVersionParsesGitTagsAndComparesSemantically() {
        let older = AppVersion(rawValue: "v0.1.9")
        let newer = AppVersion(rawValue: "0.1.10")

        XCTAssertEqual(older?.description, "0.1.9")
        XCTAssertTrue(older! < newer!)
        XCTAssertNil(AppVersion(rawValue: "0.1"))
    }

    func testRecommendedCurveMatchesCapturedProfile() {
        let curve = FanCurve.recommended(limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550))

        XCTAssertEqual(curve.points.map(\.temperature), [49, 50, 75, 90])
        XCTAssertEqual(curve.points.map(\.targetRPM), [0, 2_350, 5_068, 6_550])
    }

    func testDefaultProfilesHaveExpectedNamesAndCurves() {
        let profiles = FanProfile.defaults(limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550))

        XCTAssertEqual(profiles.map(\.name), ["Quiet", "Normal", "Aggressive Cooling"])
        XCTAssertEqual(profiles[0].curve.points.map(\.temperature), [45, 60, 80, 95])
        XCTAssertEqual(profiles[1].curve.points.map(\.temperature), [49, 50, 75, 90])
        XCTAssertEqual(profiles[2].curve.points.map(\.temperature), [35, 42, 60, 75])
    }

    func testProfileStoreMigratesLegacyCurveToNormalProfile() throws {
        let suiteName = "FanCurveTests.profileStore.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let legacyCurve = FanCurve(
            points: [
                FanCurvePoint(temperature: 50, targetRPM: 0),
                FanCurvePoint(temperature: 70, targetRPM: 2_350)
            ],
            source: .cpu
        )
        let store = FanProfileStore(userDefaults: userDefaults)
        let storage = store.load(
            defaultProfiles: FanProfile.defaults(limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550)),
            legacyCurve: legacyCurve
        )

        let normalProfile = try XCTUnwrap(storage.profiles.first { $0.name == "Normal" })
        XCTAssertEqual(normalProfile.curve, legacyCurve)
        XCTAssertEqual(storage.activeProfileID, normalProfile.id)

        store.save(profiles: storage.profiles, activeProfileID: storage.activeProfileID)
        let reloaded = store.load(defaultProfiles: [], legacyCurve: nil)
        XCTAssertEqual(reloaded.profiles, storage.profiles)
        XCTAssertEqual(reloaded.activeProfileID, storage.activeProfileID)
    }

    func testCalculatorInterpolatesBetweenTwoPoints() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 40, targetRPM: 2_350),
                FanCurvePoint(temperature: 80, targetRPM: 5_050)
            ],
            source: .cpu
        )
        let calculator = FanCurveCalculator()
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)

        XCTAssertEqual(calculator.targetRPM(for: 60, curve: curve, limits: limits), 3_700)
    }

    func testValidatorRejectsDecreasingSpeed() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 40, targetRPM: 4_000),
                FanCurvePoint(temperature: 80, targetRPM: 3_000)
            ],
            source: .hottestProcessor
        )
        let validator = FanCurveValidator()

        XCTAssertThrowsError(try validator.validate(curve, limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_000))) { error in
            XCTAssertEqual(error as? FanCurveValidationError, .speedDecreases)
        }
    }

    func testCalculatorClampsOutsideCurve() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 50, targetRPM: 2_350),
                FanCurvePoint(temperature: 90, targetRPM: 5_000)
            ],
            source: .gpu
        )
        let calculator = FanCurveCalculator()
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)

        XCTAssertEqual(calculator.targetRPM(for: 20, curve: curve, limits: limits), 2_350)
        XCTAssertEqual(calculator.targetRPM(for: 100, curve: curve, limits: limits), 5_000)
    }

    func testZeroRPMIsAllowedAtTheMinimumCurveTemperature() throws {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: FanCurveTemperatureLimits.minimum, targetRPM: 0),
                FanCurvePoint(temperature: 60, targetRPM: 2_350)
            ],
            source: .cpu
        )
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)

        XCTAssertNoThrow(try FanCurveValidator().validate(curve, limits: limits))
        XCTAssertEqual(FanCurveCalculator().targetRPM(for: 35, curve: curve, limits: limits), 0)
    }

    func testZeroRPMIsRejectedBelowTheMinimumCurveTemperature() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: FanCurveTemperatureLimits.minimum - 1, targetRPM: 0),
                FanCurvePoint(temperature: 60, targetRPM: 2_350)
            ],
            source: .cpu
        )

        XCTAssertThrowsError(
            try FanCurveValidator().validate(curve, limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_000))
        ) { error in
            XCTAssertEqual(error as? FanCurveValidationError, .temperatureOutOfBounds)
        }
    }

    func testForbiddenRPMRangeIsRejected() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 49, targetRPM: 0),
                FanCurvePoint(temperature: 50, targetRPM: 2_349)
            ],
            source: .cpu
        )

        XCTAssertThrowsError(
            try FanCurveValidator().validate(curve, limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550))
        ) { error in
            XCTAssertEqual(error as? FanCurveValidationError, .speedInForbiddenRange)
        }
    }

    func testMinimumAllowedNonZeroRPMIsAccepted() throws {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 49, targetRPM: 0),
                FanCurvePoint(temperature: 50, targetRPM: FanCurveRPMPolicy.minimumNonZeroRPM)
            ],
            source: .cpu
        )

        XCTAssertNoThrow(try FanCurveValidator().validate(curve, limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_550)))
    }

    func testCalculatorKeepsZeroRPMOutOfForbiddenRange() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 49, targetRPM: 0),
                FanCurvePoint(temperature: 50, targetRPM: FanCurveRPMPolicy.minimumNonZeroRPM)
            ],
            source: .cpu
        )
        let calculator = FanCurveCalculator()
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_550)

        XCTAssertEqual(calculator.targetRPM(for: 49.5, curve: curve, limits: limits), 0)
        XCTAssertEqual(calculator.targetRPM(for: 50, curve: curve, limits: limits), 2_350)
    }

    func testTemperatureUnitConvertsCelsiusToFahrenheit() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.displayValue(fromCelsius: 0), 32)
        XCTAssertEqual(TemperatureUnit.fahrenheit.displayValue(fromCelsius: 100), 212)
        XCTAssertEqual(TemperatureUnit.fahrenheit.celsiusValue(fromDisplayed: 95), 35)
    }

    func testTemperatureFormatterUsesSelectedUnit() {
        let formatter = TemperatureFormatter(unit: .fahrenheit)

        XCTAssertEqual(formatter.string(fromCelsius: 35), "95 °F")
        XCTAssertEqual(formatter.string(fromCelsius: nil), "—")
        XCTAssertEqual(formatter.string(fromCelsius: 35, includesUnit: false), "95")
    }

    func testMenuBarPreferencesKeepExistingValuesWhenUnitIsMissing() throws {
        let data = #"{"updateInterval":5,"displayMode":"temperatureAndRPM"}"#.data(using: .utf8)!
        let preferences = try JSONDecoder().decode(MenuBarPreferences.self, from: data)

        XCTAssertEqual(preferences.updateInterval, .fiveSeconds)
        XCTAssertEqual(preferences.displayMode, .temperatureAndRPM)
        XCTAssertEqual(preferences.temperatureUnit, .celsius)
    }

    func testAppleSMCReadOnlyProbe() async throws {
        guard ProcessInfo.processInfo.environment["FANCURVE_HARDWARE_TEST"] == "1" else {
            return
        }

        let service = try AppleSMCHardwareService()
        let snapshot = try await service.snapshot()

        XCTAssertFalse(snapshot.fans.isEmpty)
        XCTAssertNotNil(snapshot.cpuTemperature)
        XCTAssertNotNil(snapshot.gpuTemperature)

        let device = try SMCDevice()
        XCTAssertTrue(device.canControlFans())
    }

}
