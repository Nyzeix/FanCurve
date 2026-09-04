// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FanCurve",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FanCurve", targets: ["FanCurve"]),
        .executable(name: "FanCurveHelper", targets: ["FanCurveHelper"])
    ],
    targets: [
        .target(
            name: "FanCurveSMC",
            path: "Sources/FanCurveSMC"
        ),
        .target(
            name: "FanCurveXPC",
            path: "Sources/FanCurveXPC"
        ),
        .executableTarget(
            name: "FanCurve",
            dependencies: ["FanCurveSMC", "FanCurveXPC"],
            path: "Sources/FanCurve"
        ),
        .executableTarget(
            name: "FanCurveHelper",
            dependencies: ["FanCurveSMC", "FanCurveXPC"],
            path: "Sources/FanCurveHelper"
        ),
        .testTarget(
            name: "FanCurveTests",
            dependencies: ["FanCurve", "FanCurveSMC"],
            path: "Tests/FanCurveTests"
        )
    ]
)
