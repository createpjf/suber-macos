import AppKit
import SwiftUI

/// In-memory + disk cache for subscription favicons.
final class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDirectory: URL
    private let session: URLSession

    private init() {
        // Setup disk cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("com.subreminder.favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Memory cache limits
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB

        // URL session with caching
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 10_000_000, diskCapacity: 50_000_000)
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Get cached image synchronously (memory or disk).
    func cachedImage(for key: String) -> NSImage? {
        let nsKey = key as NSString

        // 1. Check memory cache
        if let image = memoryCache.object(forKey: nsKey) {
            return image
        }

        // 2. Check disk cache
        let diskPath = diskCachePath(for: key)
        if let data = try? Data(contentsOf: diskPath),
           let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: nsKey)
            return image
        }

        return nil
    }

    /// Load image from URL with caching.
    func loadImage(for key: String, url: URL) async -> NSImage? {
        // Check caches first
        if let cached = cachedImage(for: key) {
            return cached
        }

        // Fetch from network
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 100, // filter out tiny error responses
                  let image = NSImage(data: data) else {
                return nil
            }

            // Store in memory cache
            let nsKey = key as NSString
            memoryCache.setObject(image, forKey: nsKey)

            // Store on disk (fire-and-forget)
            let diskPath = diskCachePath(for: key)
            try? data.write(to: diskPath, options: .atomic)

            return image
        } catch {
            return nil
        }
    }

    /// Build favicon URLs to try, in priority order.
    func faviconURLs(for subscription: Subscription) -> [URL] {
        var urls: [URL] = []

        // 1. Direct logo URL from subscription data
        if let logo = subscription.logo, let url = URL(string: logo) {
            urls.append(url)
        }

        // 2. Extract domain from subscription URL
        let domain = extractDomain(from: subscription.url)

        if let domain = domain {
            // Google high-res favicon
            if let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") {
                urls.append(url)
            }
            // DuckDuckGo icons (often higher quality)
            if let url = URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico") {
                urls.append(url)
            }
        }

        return urls
    }

    /// Cache key for a subscription.
    func cacheKey(for subscription: Subscription) -> String {
        if let domain = extractDomain(from: subscription.url) {
            return "favicon_\(domain)"
        }
        return "favicon_\(subscription.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
    }

    /// Clear all cached favicons.
    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func diskCachePath(for key: String) -> URL {
        let sanitized = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDirectory.appendingPathComponent(sanitized)
    }

    private func extractDomain(from urlString: String?) -> String? {
        guard var str = urlString, !str.isEmpty else { return nil }

        // Add scheme if missing
        if !str.contains("://") {
            str = "https://\(str)"
        }

        guard let url = URL(string: str), let host = url.host else {
            // Try treating the whole string as a domain
            let cleaned = str.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .components(separatedBy: "/").first ?? str
            return cleaned.isEmpty ? nil : cleaned
        }

        return host
    }
}
