import AppKit
import Combine
import Foundation

protocol UpdateReleaseService: Sendable {
    func latestRelease() async throws -> AvailableRelease?
}

protocol UpdateInstaller: Sendable {
    func install(_ release: AvailableRelease) async throws
}

@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var availableRelease: AvailableRelease?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var isUpdatePromptVisible = false
    @Published private(set) var automaticallyChecksForUpdates: Bool

    let currentVersion: AppVersion

    private let releaseService: any UpdateReleaseService
    private let installer: any UpdateInstaller
    private var checkTask: Task<Void, Never>?
    private var automaticCheckTask: Task<Void, Never>?

    init(
        releaseService: any UpdateReleaseService = GitHubReleaseService(),
        installer: any UpdateInstaller = LocalApplicationUpdateInstaller()
    ) {
        self.releaseService = releaseService
        self.installer = installer
        currentVersion = Self.readCurrentVersion()
            ?? AppVersion(rawValue: "0.0.0")!
        lastCheckDate = Self.loadLastCheckDate()
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool ?? true

        automaticCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))

            guard !Task.isCancelled else { return }
            await self?.checkIfNeeded()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(86_400))
                guard !Task.isCancelled else { return }
                await self?.checkIfNeeded()
            }
        }
    }

    deinit {
        checkTask?.cancel()
        automaticCheckTask?.cancel()
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            true
        default:
            false
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.automaticChecksKey)

        if enabled {
            Task { await checkIfNeeded() }
        }
    }

    func checkForUpdates() {
        guard checkTask == nil else { return }

        checkTask = Task { [weak self] in
            await self?.performCheck()
            self?.checkTask = nil
        }
    }

    func dismissUpdatePrompt() {
        isUpdatePromptVisible = false
    }

    func installAvailableUpdate(
        preparingApplication: @escaping @MainActor () async -> Bool
    ) async {
        guard let release = availableRelease, !isBusy else { return }

        guard await preparingApplication() else {
            state = .failed(.installationFailed("Fan control could not be returned to macOS."))
            return
        }

        isUpdatePromptVisible = false
        state = .downloading

        do {
            state = .installing
            try await installer.install(release)
            state = .installed(release.version)
            try await relaunchApplication()
        } catch let error as UpdateError {
            state = .failed(error)
        } catch {
            state = .failed(.installationFailed(error.localizedDescription))
        }
    }

    private func checkIfNeeded() async {
        guard automaticallyChecksForUpdates else { return }
        guard let lastCheckDate else {
            checkForUpdates()
            return
        }

        guard Date().timeIntervalSince(lastCheckDate) >= Self.checkInterval else { return }
        checkForUpdates()
    }

    private func performCheck() async {
        state = .checking

        do {
            let release = try await releaseService.latestRelease()
            let checkDate = Date()
            lastCheckDate = checkDate
            Self.saveLastCheckDate(checkDate)

            guard let release, release.version > currentVersion else {
                availableRelease = nil
                isUpdatePromptVisible = false
                state = .upToDate(checkDate)
                return
            }

            availableRelease = release
            isUpdatePromptVisible = true
            state = .available(release)
        } catch let error as UpdateError {
            state = .failed(error)
        } catch {
            state = .failed(.network(error.localizedDescription))
        }
    }

    private func relaunchApplication() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]

        do {
            try process.run()
        } catch {
            throw UpdateError.relaunchFailed
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.relaunchFailed
        }

        try? await Task.sleep(for: .milliseconds(500))
        NSApplication.shared.terminate(nil)
    }

    private static func readCurrentVersion() -> AppVersion? {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }
        return AppVersion(rawValue: version)
    }

    private static func loadLastCheckDate() -> Date? {
        guard let timestamp = UserDefaults.standard.object(forKey: lastCheckDateKey) as? Date else {
            return nil
        }
        return timestamp
    }

    private static func saveLastCheckDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastCheckDateKey)
    }

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let automaticChecksKey = "FanCurve.updates.automaticChecks"
    private static let lastCheckDateKey = "FanCurve.updates.lastCheckDate"
}
