import Foundation
import AppKit

/// Lightweight update checker using GitHub Releases API.
enum UpdateService {

    // MARK: - Types

    struct Release {
        let version: String     // "1.2.0"
        let tagName: String     // "v1.2.0"
        let notes: String       // release body markdown
        let dmgURL: URL?        // first .dmg asset download URL
        let publishedAt: Date?
    }

    enum UpdateError: LocalizedError {
        case networkError(String)
        case noRelease
        case noDMG

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return msg
            case .noRelease: return "No release found."
            case .noDMG: return "No DMG file in release."
            }
        }
    }

    // MARK: - Config

    private static let repoOwner = "createpjf"
    private static let repoName = "suber-macos"
    private static let apiURL = "https://api.github.com/repos/createpjf/suber-macos/releases/latest"

    // MARK: - Current Version

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Check for Update

    /// Check GitHub for the latest release. Returns nil if already up-to-date.
    static func checkForUpdate() async throws -> Release? {
        guard let url = URL(string: apiURL) else { throw UpdateError.networkError("Invalid URL") }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.networkError("GitHub API returned error.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.noRelease
        }

        guard let tagName = json["tag_name"] as? String else {
            throw UpdateError.noRelease
        }

        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        // Compare versions
        guard isNewer(remoteVersion, than: currentVersion) else {
            return nil // up-to-date
        }

        // Parse release info
        let notes = json["body"] as? String ?? ""
        let publishedStr = json["published_at"] as? String
        var publishedAt: Date?
        if let str = publishedStr {
            let formatter = ISO8601DateFormatter()
            publishedAt = formatter.date(from: str)
        }

        // Find DMG asset
        var dmgURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String,
                   name.lowercased().hasSuffix(".dmg"),
                   let urlStr = asset["browser_download_url"] as? String,
                   let url = URL(string: urlStr) {
                    dmgURL = url
                    break
                }
            }
        }

        return Release(
            version: remoteVersion,
            tagName: tagName,
            notes: notes,
            dmgURL: dmgURL,
            publishedAt: publishedAt
        )
    }

    // MARK: - Version Comparison

    /// Returns true if `remote` is newer than `local` (semantic versioning).
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false // equal
    }

    // MARK: - Download

    /// Download DMG to ~/Downloads/ and open it.
    static func downloadAndOpen(_ url: URL, version: String) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.networkError("Download failed.")
        }

        // Move to ~/Downloads/
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destURL = downloads.appendingPathComponent("Suber-v\(version).dmg")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        // Open DMG
        await MainActor.run {
            NSWorkspace.shared.open(destURL)
        }

        return destURL
    }
}
