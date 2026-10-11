import Foundation

struct AvailableRelease: Codable, Hashable, Sendable {
    let version: AppVersion
    let tag: String
    let notes: String
    let assetURL: URL
    let assetSize: Int64
    let publishedAt: Date?
}

enum ReleaseFeed {
    static let repository = "polo871209/nanocast"

    static func newest(from data: Data, channel: ReleaseChannel) -> AvailableRelease? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        return
            entries
            .compactMap { release(from: $0, channel: channel) }
            .max { $0.version < $1.version }
    }

    static func offer(
        _ release: AvailableRelease?, running: AppVersion, skipped: AppVersion?
    ) -> AvailableRelease? {
        guard let release, release.version > running else { return nil }
        if let skipped, release.version <= skipped { return nil }
        return release
    }

    private static func release(from entry: Entry, channel: ReleaseChannel) -> AvailableRelease? {
        guard !entry.draft, channel.accepts(prerelease: entry.prerelease),
            let version = AppVersion(entry.tagName),
            let asset = entry.assets.first(where: { $0.name.hasSuffix(".zip") })
        else { return nil }
        return AvailableRelease(
            version: version,
            tag: entry.tagName,
            notes: ReleaseNotes.summary(of: entry.body ?? ""),
            assetURL: asset.browserDownloadURL,
            assetSize: asset.size,
            publishedAt: entry.publishedAt.flatMap { try? Date($0, strategy: .iso8601) })
    }

    private struct Entry: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft, body, assets
            case publishedAt = "published_at"
        }

        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name, size
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
