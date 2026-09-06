import CryptoKit
import Foundation

actor LocalApplicationUpdateInstaller: UpdateInstaller {
    private let fileManager: FileManager
    private let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func install(_ release: AvailableRelease) async throws {
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("FanCurve-update-\(UUID().uuidString)", isDirectory: true)
        let extractedDirectory = workingDirectory.appendingPathComponent("Extracted", isDirectory: true)
        let archiveURL = workingDirectory.appendingPathComponent(release.asset.name)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
            try await download(release.asset.downloadURL, to: archiveURL)
            try verifyChecksum(of: archiveURL, expected: release.asset.sha256)
            try extract(archiveURL, to: extractedDirectory)

            let applicationURL = try findApplication(in: extractedDirectory)
            try validate(applicationURL, for: release)
            try replaceCurrentApplication(with: applicationURL)
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.installationFailed(error.localizedDescription)
        }

    }

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("FanCurve update installer", forHTTPHeaderField: "User-Agent")

        let temporaryURL: URL
        let response: URLResponse

        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.network("GitHub returned an unexpected download response.")
        }

        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private func verifyChecksum(of fileURL: URL, expected: String) throws {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw UpdateError.invalidArchive
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == expected.lowercased() else {
            throw UpdateError.checksumMismatch
        }
    }

    private func extract(_ archiveURL: URL, to destination: URL) throws {
        _ = try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, destination.path]
        )
    }

    private func findApplication(in directory: URL) throws -> URL {
        let expectedApplication = directory
            .appendingPathComponent("FanCurve", isDirectory: true)
            .appendingPathComponent("FanCurve.app", isDirectory: true)

        if fileManager.fileExists(atPath: expectedApplication.path) {
            return expectedApplication
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw UpdateError.invalidArchive
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }

        throw UpdateError.invalidArchive
    }

    private func validate(_ applicationURL: URL, for release: AvailableRelease) throws {
        guard let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == "FanCurve",
              let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(rawValue: versionString) == release.version,
              fileManager.isExecutableFile(atPath: applicationURL.appendingPathComponent("Contents/MacOS/FanCurve").path),
              fileManager.isExecutableFile(atPath: applicationURL.appendingPathComponent("Contents/Library/PrivilegedHelperTools/FanCurve.helper").path) else {
            throw UpdateError.incompatibleApplication
        }

        guard isCompatibleWithCurrentSystem(bundle: bundle),
              containsArm64Executable(at: applicationURL.appendingPathComponent("Contents/MacOS/FanCurve")),
              containsArm64Executable(at: applicationURL.appendingPathComponent("Contents/Library/PrivilegedHelperTools/FanCurve.helper")) else {
            throw UpdateError.incompatibleSystem
        }

        do {
            _ = try runProcess(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", applicationURL.path]
            )
        } catch {
            throw UpdateError.incompatibleApplication
        }
    }

    private func isCompatibleWithCurrentSystem(bundle: Bundle) -> Bool {
        guard let minimumVersion = bundle.object(
            forInfoDictionaryKey: "LSMinimumSystemVersion"
        ) as? String else {
            return true
        }

        let required = minimumVersion.split(separator: ".").compactMap { Int($0) }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let running = [current.majorVersion, current.minorVersion, current.patchVersion]

        for index in 0..<max(required.count, running.count) {
            let requiredComponent = index < required.count ? required[index] : 0
            let runningComponent = index < running.count ? running[index] : 0
            if requiredComponent != runningComponent {
                return requiredComponent < runningComponent
            }
        }

        return true
    }

    private func containsArm64Executable(at executableURL: URL) -> Bool {
        guard let output = try? runProcess(executable: "/usr/bin/file", arguments: [executableURL.path]) else {
            return false
        }
        return output.contains("arm64")
    }

    private func replaceCurrentApplication(with stagedURL: URL) throws {
        let currentApplicationURL = Bundle.main.bundleURL
        let updateURL = currentApplicationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".FanCurve.app.update-\(UUID().uuidString)", isDirectory: true)
        let backupURL = currentApplicationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".FanCurve.app.previous", isDirectory: true)

        do {
            try fileManager.copyItem(at: stagedURL, to: updateURL)
            try? fileManager.removeItem(at: backupURL)
            _ = try fileManager.replaceItemAt(
                currentApplicationURL,
                withItemAt: updateURL,
                backupItemName: backupURL.lastPathComponent,
                options: .usingNewMetadataOnly
            )
        } catch {
            try? fileManager.removeItem(at: updateURL)
            try installWithAdministratorPrivileges(
                stagedURL: stagedURL,
                currentApplicationURL: currentApplicationURL,
                backupURL: backupURL
            )
        }
    }

    private func installWithAdministratorPrivileges(
        stagedURL: URL,
        currentApplicationURL: URL,
        backupURL: URL
    ) throws {
        let incomingURL = currentApplicationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".FanCurve.app.incoming-\(UUID().uuidString)", isDirectory: true)
        let shellCommand = """
        set -eu
        incoming_path=\(shellQuote(incomingURL.path))
        current_path=\(shellQuote(currentApplicationURL.path))
        backup_path=\(shellQuote(backupURL.path))
        staged_path=\(shellQuote(stagedURL.path))
        /bin/rm -rf "$incoming_path"
        /usr/bin/ditto --norsrc --noextattr "$staged_path" "$incoming_path"
        /bin/rm -rf "$backup_path"
        if [ -e "$current_path" ]; then /bin/mv "$current_path" "$backup_path"; fi
        if ! /bin/mv "$incoming_path" "$current_path"; then
            if [ -e "$backup_path" ]; then /bin/mv "$backup_path" "$current_path"; fi
            exit 1
        fi
        """

        let appleScript = "do shell script \(appleScriptStringLiteral(shellCommand)) with administrator privileges"
        do {
            _ = try runProcess(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError.authorizationRequired
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: error, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.installationFailed(message ?? "The system command failed.")
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
