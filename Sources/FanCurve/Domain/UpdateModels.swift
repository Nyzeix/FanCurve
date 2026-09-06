import Foundation

struct AppVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(rawValue: String) {
        let normalizedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" || $0 == "V" })
        let components = normalizedValue.split(separator: ".", omittingEmptySubsequences: false)

        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct UpdateAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let sha256: String
    let sizeInBytes: Int64
}

struct AvailableRelease: Identifiable, Equatable, Sendable {
    let version: AppVersion
    let tagName: String
    let title: String
    let releaseNotes: String
    let publishedAt: Date?
    let asset: UpdateAsset

    var id: String { tagName }
}

enum UpdateError: LocalizedError, Equatable, Sendable {
    case network(String)
    case invalidRelease
    case releaseAssetUnavailable
    case invalidArchive
    case checksumMismatch
    case incompatibleApplication
    case incompatibleSystem
    case authorizationRequired
    case installationFailed(String)
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .network:
            "Unable to check for updates. Verify your internet connection."
        case .invalidRelease:
            "The latest release information is invalid."
        case .releaseAssetUnavailable:
            "The latest release does not contain a compatible FanCurve package."
        case .invalidArchive:
            "The downloaded update archive is invalid."
        case .checksumMismatch:
            "The downloaded update failed its integrity check."
        case .incompatibleApplication:
            "The downloaded update is not a compatible FanCurve application."
        case .incompatibleSystem:
            "The downloaded update is not compatible with this Mac or macOS version."
        case .authorizationRequired:
            "Administrator authorization is required to replace FanCurve in the Applications folder."
        case .installationFailed(let message):
            "The update could not be installed: \(message)"
        case .relaunchFailed:
            "The update was installed, but FanCurve could not be relaunched."
        }
    }
}

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(Date)
    case available(AvailableRelease)
    case downloading
    case installing
    case installed(AppVersion)
    case failed(UpdateError)
}
