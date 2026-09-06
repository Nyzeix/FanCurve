import Foundation

struct GitHubReleaseService: UpdateReleaseService {
    private let repositoryURL = URL(string: "https://api.github.com/repos/Nyzeix/FanCurve/releases/latest")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func latestRelease() async throws -> AvailableRelease? {
        var request = URLRequest(url: repositoryURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FanCurve update checker", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.network("GitHub returned an unexpected response.")
        }

        let payload: GitHubReleasePayload
        do {
            payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw UpdateError.invalidRelease
        }

        guard !payload.draft, !payload.prerelease,
              let version = AppVersion(rawValue: payload.tagName) else {
            return nil
        }

        guard let archive = payload.assets.first(where: { $0.name == "FanCurve-macOS-arm64.zip" }),
              let downloadURL = URL(string: archive.browserDownloadURL),
              downloadURL.scheme == "https",
              downloadURL.host == "github.com",
              let sha256 = normalizedSHA256(archive.digest) else {
            throw UpdateError.releaseAssetUnavailable
        }

        let publishedAt = payload.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let releaseNotes = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return AvailableRelease(
            version: version,
            tagName: payload.tagName,
            title: payload.name ?? "FanCurve \(version)",
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            asset: UpdateAsset(
                name: archive.name,
                downloadURL: downloadURL,
                sha256: sha256,
                sizeInBytes: Int64(archive.size)
            )
        )
    }

    private func normalizedSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let value = digest.lowercased().hasPrefix("sha256:")
            ? String(digest.dropFirst("sha256:".count))
            : digest
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return normalized
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let digest: String?
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
        case size
    }
}
