import AppKit
import SwiftUI

/// In-memory + disk cache for subscription favicons.
final class ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDirectory: URL
    private let session: URLSession
    /// In-flight request dedup: prevents duplicate network fetches for the same cache key.
    private var inFlightTasks: [String: Task<NSImage?, Never>] = []
    private let taskLock = NSLock()
    /// Serial queue for disk cache read/write to prevent concurrent file access.
    private let diskQueue = DispatchQueue(label: "com.subreminder.diskcache", qos: .utility)

    private init() {
        // Setup disk cache directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
cacheDirectory = caches.appendingPathComponent("com.suber.favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Memory cache limits (keep lightweight for menu bar app)
        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 15 * 1024 * 1024 // 15MB

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

        // 2. Check disk cache (synchronous read on disk queue)
        let diskPath = diskCachePath(for: key)
        let image: NSImage? = diskQueue.sync {
            guard let data = try? Data(contentsOf: diskPath) else { return nil }
            return NSImage(data: data)
        }
        if let image = image {
            memoryCache.setObject(image, forKey: nsKey)
            return image
        }

        return nil
    }

    /// Load image from URL with caching and in-flight dedup.
    func loadImage(for key: String, url: URL) async -> NSImage? {
        // Check caches first
        if let cached = cachedImage(for: key) {
            return cached
        }

        // Dedup: reuse existing in-flight task for same key
        taskLock.lock()
        if let existing = inFlightTasks[key] {
            taskLock.unlock()
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      data.count > 100,
                      let image = NSImage(data: data) else {
                    return nil
                }

                // Store in memory cache with cost
                let nsKey = key as NSString
                memoryCache.setObject(image, forKey: nsKey, cost: data.count)

                // Store on disk via serial queue (fire-and-forget)
                let diskPath = self.diskCachePath(for: key)
                self.diskQueue.async {
                    try? data.write(to: diskPath, options: .atomic)
                }

                return image
            } catch {
                return nil
            }
        }
        inFlightTasks[key] = task
        taskLock.unlock()

        let result = await task.value

        // Clean up in-flight entry
        taskLock.lock()
        inFlightTasks.removeValue(forKey: key)
        taskLock.unlock()

        return result
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
