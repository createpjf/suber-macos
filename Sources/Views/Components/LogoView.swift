import SwiftUI

struct LogoView: View {
    let subscription: Subscription
    var size: CGFloat = 32

    var body: some View {
        if let url = faviconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
                case .failure:
                    initialFallback
                default:
                    initialFallback
                        .opacity(0.5)
                }
            }
        } else {
            initialFallback
        }
    }

    private var initialFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(Theme.bgSecondary)
            Text(String(subscription.name.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(width: size, height: size)
    }

    private var faviconURL: URL? {
        // Prefer stored logo URL
        if let logo = subscription.logo, let url = URL(string: logo) {
            return url
        }
        // Fall back to Google Favicons
        guard let urlString = subscription.url,
              let parsed = URL(string: urlString),
              let host = parsed.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }
}
