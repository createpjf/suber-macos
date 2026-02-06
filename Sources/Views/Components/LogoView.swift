import SwiftUI

struct LogoView: View {
    let subscription: Subscription
    var size: CGFloat = 32

    @State private var loadedImage: NSImage?
    @State private var loadFailed = false

    private let cache = ImageCache.shared

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
                    .transition(.opacity)
            } else {
                initialFallback
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.15), value: loadedImage != nil)
        .task(id: cacheKey) {
            await loadFavicon()
        }
    }

    private var cacheKey: String {
        cache.cacheKey(for: subscription)
    }

    private var initialFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Theme.bgSecondary)
            Text(String(subscription.name.prefix(1)).uppercased())
                .font(AppFont.bold(size * 0.45))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(width: size, height: size)
    }

    private func loadFavicon() async {
        let key = cacheKey

        // 1. Check cache immediately (sync)
        if let cached = cache.cachedImage(for: key) {
            loadedImage = cached
            return
        }

        // 2. Fetch from network, trying URLs in priority order
        let urls = cache.faviconURLs(for: subscription)
        guard !urls.isEmpty else {
            loadFailed = true
            return
        }

        for url in urls {
            if let image = await cache.loadImage(for: key, url: url) {
                await MainActor.run {
                    loadedImage = image
                }
                return
            }
        }

        loadFailed = true
    }
}
