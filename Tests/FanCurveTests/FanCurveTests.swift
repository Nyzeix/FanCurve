import XCTest
import FanCurveSMC
@testable import FanCurve

final class FanCurveTests: XCTestCase {
    func testCalculatorInterpolatesBetweenTwoPoints() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 40, targetRPM: 1_000),
                FanCurvePoint(temperature: 80, targetRPM: 5_000)
            ],
            source: .cpu
        )
        let calculator = FanCurveCalculator()
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)

        XCTAssertEqual(calculator.targetRPM(for: 60, curve: curve, limits: limits), 3_000)
    }

    func testValidatorRejectsDecreasingSpeed() {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: 40, targetRPM: 3_000),
                FanCurvePoint(temperature: 80, targetRPM: 2_000)
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
                FanCurvePoint(temperature: 50, targetRPM: 1_500),
                FanCurvePoint(temperature: 90, targetRPM: 5_000)
            ],
            source: .gpu
        )
        let calculator = FanCurveCalculator()
        let limits = FanLimits(minimumRPM: 1_000, maximumRPM: 6_000)

        XCTAssertEqual(calculator.targetRPM(for: 20, curve: curve, limits: limits), 1_500)
        XCTAssertEqual(calculator.targetRPM(for: 100, curve: curve, limits: limits), 5_000)
    }

    func testZeroRPMIsAllowedAtTheMinimumCurveTemperature() throws {
        let curve = FanCurve(
            points: [
                FanCurvePoint(temperature: FanCurveTemperatureLimits.minimum, targetRPM: 0),
                FanCurvePoint(temperature: 60, targetRPM: 2_000)
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
                FanCurvePoint(temperature: 60, targetRPM: 2_000)
            ],
            source: .cpu
        )

        XCTAssertThrowsError(
            try FanCurveValidator().validate(curve, limits: FanLimits(minimumRPM: 1_000, maximumRPM: 6_000))
        ) { error in
            XCTAssertEqual(error as? FanCurveValidationError, .temperatureOutOfBounds)
        }
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
