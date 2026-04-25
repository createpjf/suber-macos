import Foundation

/// Database of well-known subscription services for OCR text matching and
/// v1.6 One-Tap Cancel URL resolution.
enum KnownServices {
    struct Service {
        let names: [String]           // name variants (case-insensitive matching)
        let domain: String            // primary domain
        let category: String          // maps to AppConstants.categories
        let defaultCycle: BillingCycle
        /// v1.6: direct cancel-page URL. Nil → caller falls back to
        /// DuckDuckGo search via OneTapCancelService. `itms-apps://`
        /// routes to the Mac App Store Subscriptions screen for services
        /// that only let you cancel there (Apple-billed subs, some Chinese
        /// services that hide web-cancel behind a native-app paywall).
        let cancellationURL: String?

        init(
            names: [String],
            domain: String,
            category: String,
            defaultCycle: BillingCycle,
            cancellationURL: String? = nil
        ) {
            self.names = names
            self.domain = domain
            self.category = category
            self.defaultCycle = defaultCycle
            self.cancellationURL = cancellationURL
        }
    }

    // MARK: - Apple Subscriptions deep-link
    //
    // itms-apps://apps.apple.com/account/subscriptions jumps straight to the
    // Subscriptions pane. Works for any Apple-billed sub: iCloud+, Apple TV+,
    // Apple Music, Apple Arcade, Apple Fitness+, and any app purchased
    // through Apple's in-app purchase flow. Consolidated as a constant so
    // the URL changes (if Apple ever updates it) only need one edit.
    private static let appleSubscriptionsURL = "itms-apps://apps.apple.com/account/subscriptions"

    // MARK: - Database

    static let all: [Service] = [
        // Streaming
        Service(names: ["Netflix", "NETFLIX"], domain: "netflix.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.netflix.com/cancelplan"),
        Service(names: ["Disney+", "Disney Plus", "DISNEY+"], domain: "disneyplus.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.disneyplus.com/account/cancel-subscription"),
        Service(names: ["Hulu", "HULU"], domain: "hulu.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://secure.hulu.com/account/cancel"),
        Service(names: ["HBO Max", "HBO", "Max"], domain: "max.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://auth.max.com/customer-service/billing-invoices"),
        Service(names: ["Amazon Prime", "Prime Video", "Amazon Prime Video"], domain: "amazon.com", category: "Streaming", defaultCycle: .yearly,
                cancellationURL: "https://www.amazon.com/gp/primecentral"),
        Service(names: ["Apple TV+", "Apple TV Plus"], domain: "tv.apple.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["Paramount+", "Paramount Plus"], domain: "paramountplus.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.paramountplus.com/account/cancel-subscription/"),
        Service(names: ["Peacock", "Peacock Premium"], domain: "peacocktv.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.peacocktv.com/account/plans"),
        Service(names: ["Crunchyroll", "CRUNCHYROLL"], domain: "crunchyroll.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.crunchyroll.com/account/membership"),
        Service(names: ["YouTube Premium", "YouTube Music", "YouTube TV"], domain: "youtube.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.youtube.com/paid_memberships"),
        Service(names: ["Twitch", "Twitch Turbo"], domain: "twitch.tv", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://www.twitch.tv/subscriptions"),

        // Chinese Streaming (Apple Music / iCloud live under itms-apps; these
        // use their own portals. Some fall back to DuckDuckGo search.)
        Service(names: ["爱奇艺", "iQIYI", "iQiyi", "IQIYI"], domain: "iqiyi.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://account.iqiyi.com/user/memberservice"),
        Service(names: ["腾讯视频", "Tencent Video"], domain: "v.qq.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: nil),
        Service(names: ["优酷", "Youku", "YOUKU"], domain: "youku.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://jiaofei.youku.com/vip/memberBalance"),
        Service(names: ["芒果TV", "MangoTV"], domain: "mgtv.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: nil),
        Service(names: ["哔哩哔哩", "bilibili", "B站", "Bilibili"], domain: "bilibili.com", category: "Streaming", defaultCycle: .monthly,
                cancellationURL: "https://account.bilibili.com/big"),

        // Music
        Service(names: ["Spotify", "SPOTIFY", "Spotify Premium"], domain: "spotify.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: "https://www.spotify.com/account/subscription/"),
        Service(names: ["Apple Music"], domain: "music.apple.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["Tidal", "TIDAL"], domain: "tidal.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: "https://my.account.tidal.com/subscription"),
        Service(names: ["Deezer", "DEEZER"], domain: "deezer.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: "https://www.deezer.com/account/offer"),
        Service(names: ["网易云音乐", "NetEase Music", "NetEase Cloud Music"], domain: "music.163.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: nil),  // App-only — DuckDuckGo fallback
        Service(names: ["QQ音乐", "QQ Music"], domain: "y.qq.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: nil),
        Service(names: ["SoundCloud", "SoundCloud Go"], domain: "soundcloud.com", category: "Music", defaultCycle: .monthly,
                cancellationURL: "https://soundcloud.com/settings/subscription"),

        // AI
        Service(names: ["ChatGPT", "ChatGPT Plus", "OpenAI"], domain: "openai.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://chat.openai.com/"),   // in-app Settings → Subscription
        Service(names: ["Claude", "Claude Pro", "Anthropic"], domain: "anthropic.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://claude.ai/settings/billing"),
        Service(names: ["Midjourney", "MidJourney", "MIDJOURNEY"], domain: "midjourney.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://www.midjourney.com/account/"),
        Service(names: ["GitHub Copilot", "Copilot"], domain: "github.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://github.com/settings/billing/summary"),
        Service(names: ["Cursor", "Cursor Pro"], domain: "cursor.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://www.cursor.com/settings"),
        Service(names: ["Perplexity", "Perplexity Pro"], domain: "perplexity.ai", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://www.perplexity.ai/settings/account"),
        Service(names: ["Gemini", "Google Gemini", "Gemini Advanced"], domain: "gemini.google.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: "https://one.google.com/storage"),
        Service(names: ["Poe", "Poe Premium"], domain: "poe.com", category: "AI", defaultCycle: .monthly,
                cancellationURL: nil),

        // Software
        Service(names: ["Adobe", "Adobe Creative Cloud", "Creative Cloud", "Photoshop", "Lightroom", "Illustrator", "Premiere Pro"], domain: "adobe.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://account.adobe.com/plans"),
        Service(names: ["Microsoft 365", "Office 365", "Microsoft Office"], domain: "microsoft.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://account.microsoft.com/services/"),
        Service(names: ["JetBrains", "IntelliJ", "WebStorm", "PyCharm", "PhpStorm"], domain: "jetbrains.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://account.jetbrains.com/licenses"),
        Service(names: ["1Password", "1password"], domain: "1password.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://my.1password.com/billing"),
        Service(names: ["LastPass", "Lastpass"], domain: "lastpass.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://lastpass.com/misc_account.php"),
        Service(names: ["Dashlane"], domain: "dashlane.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://app.dashlane.com/account/subscription"),
        Service(names: ["Setapp", "SETAPP"], domain: "setapp.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://my.setapp.com/subscription"),
        Service(names: ["CleanMyMac", "CleanMyMac X"], domain: "macpaw.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://macpaw.com/account/subscriptions"),

        // Cloud Storage
        Service(names: ["iCloud", "iCloud+", "Apple iCloud"], domain: "icloud.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["Google One", "Google Drive", "Google Storage"], domain: "one.google.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: "https://one.google.com/storage"),
        Service(names: ["Dropbox", "Dropbox Plus", "Dropbox Professional"], domain: "dropbox.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: "https://www.dropbox.com/account/plan"),
        Service(names: ["OneDrive", "Microsoft OneDrive"], domain: "onedrive.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: "https://account.microsoft.com/services/"),
        Service(names: ["Box", "Box.com"], domain: "box.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: "https://app.box.com/account"),
        Service(names: ["百度网盘", "Baidu Pan", "百度云"], domain: "pan.baidu.com", category: "Cloud Storage", defaultCycle: .monthly,
                cancellationURL: nil),

        // Productivity
        Service(names: ["Notion", "NOTION", "Notion Plus", "Notion AI"], domain: "notion.so", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://www.notion.so/my-integrations"),
        Service(names: ["Figma", "FIGMA", "Figma Professional"], domain: "figma.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://www.figma.com/settings/billing"),
        Service(names: ["Slack", "SLACK", "Slack Pro"], domain: "slack.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://my.slack.com/admin/billing"),
        Service(names: ["Linear", "LINEAR"], domain: "linear.app", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://linear.app/settings/billing"),
        Service(names: ["Todoist", "Todoist Pro"], domain: "todoist.com", category: "Productivity", defaultCycle: .yearly,
                cancellationURL: "https://todoist.com/app/settings/billing"),
        Service(names: ["Trello", "Trello Premium"], domain: "trello.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://trello.com/billing"),
        Service(names: ["Asana", "Asana Premium"], domain: "asana.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://app.asana.com/0/admin/billing"),
        Service(names: ["Monday.com", "Monday"], domain: "monday.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: nil),
        Service(names: ["Canva", "Canva Pro"], domain: "canva.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://www.canva.com/account/billing-and-plans"),
        Service(names: ["Miro", "Miro Board"], domain: "miro.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://miro.com/app/settings/user-profile/"),
        Service(names: ["Evernote", "Evernote Premium"], domain: "evernote.com", category: "Productivity", defaultCycle: .yearly,
                cancellationURL: "https://www.evernote.com/Settings.action"),
        Service(names: ["Bear", "Bear Pro"], domain: "bear.app", category: "Productivity", defaultCycle: .yearly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["Craft", "Craft Pro"], domain: "craft.do", category: "Productivity", defaultCycle: .yearly,
                cancellationURL: "https://www.craft.do/settings/billing"),

        // Education
        Service(names: ["Coursera", "Coursera Plus"], domain: "coursera.org", category: "Education", defaultCycle: .monthly,
                cancellationURL: "https://www.coursera.org/account-settings/plans"),
        Service(names: ["Udemy"], domain: "udemy.com", category: "Education", defaultCycle: .oneTime,
                cancellationURL: "https://www.udemy.com/user/edit-account/"),
        Service(names: ["Skillshare", "Skillshare Premium"], domain: "skillshare.com", category: "Education", defaultCycle: .yearly,
                cancellationURL: "https://www.skillshare.com/settings/payments"),
        Service(names: ["MasterClass", "Masterclass"], domain: "masterclass.com", category: "Education", defaultCycle: .yearly,
                cancellationURL: "https://www.masterclass.com/account/membership"),
        Service(names: ["Duolingo", "Duolingo Plus", "Duolingo Super"], domain: "duolingo.com", category: "Education", defaultCycle: .monthly,
                cancellationURL: "https://www.duolingo.com/settings/subscription"),
        Service(names: ["Brilliant", "Brilliant Premium"], domain: "brilliant.org", category: "Education", defaultCycle: .yearly,
                cancellationURL: "https://brilliant.org/account/"),

        // News
        Service(names: ["The New York Times", "NYT", "NY Times", "New York Times"], domain: "nytimes.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://myaccount.nytimes.com/seg/subscription"),
        Service(names: ["The Washington Post", "Washington Post"], domain: "washingtonpost.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://subscribe.washingtonpost.com/account"),
        Service(names: ["The Wall Street Journal", "WSJ", "Wall Street Journal"], domain: "wsj.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://customercenter.wsj.com/view/cancel.html"),
        Service(names: ["The Economist", "Economist"], domain: "economist.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://myaccount.economist.com/s/"),
        Service(names: ["Medium", "Medium Premium"], domain: "medium.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://medium.com/me/membership"),
        Service(names: ["Substack"], domain: "substack.com", category: "News", defaultCycle: .monthly,
                cancellationURL: "https://substack.com/account"),

        // Gaming
        Service(names: ["Xbox Game Pass", "Game Pass", "Xbox Live", "Xbox Gold"], domain: "xbox.com", category: "Gaming", defaultCycle: .monthly,
                cancellationURL: "https://account.microsoft.com/services/"),
        Service(names: ["PlayStation Plus", "PS Plus", "PS+", "PlayStation Now"], domain: "playstation.com", category: "Gaming", defaultCycle: .monthly,
                cancellationURL: "https://www.playstation.com/en-us/support/account/cancel-playstation-subscriptions/"),
        Service(names: ["Nintendo Switch Online", "Nintendo Online"], domain: "nintendo.com", category: "Gaming", defaultCycle: .yearly,
                cancellationURL: "https://accounts.nintendo.com/subscription"),
        Service(names: ["Apple Arcade"], domain: "apple.com/apple-arcade", category: "Gaming", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["EA Play", "EA Access"], domain: "ea.com", category: "Gaming", defaultCycle: .monthly,
                cancellationURL: "https://myaccount.ea.com/cp-ui/aboutme/index"),
        Service(names: ["Steam"], domain: "store.steampowered.com", category: "Gaming", defaultCycle: .oneTime,
                cancellationURL: nil),

        // Fitness
        Service(names: ["Apple Fitness+", "Apple Fitness Plus", "Fitness+"], domain: "apple.com/apple-fitness-plus", category: "Fitness", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
        Service(names: ["Peloton", "Peloton Digital"], domain: "onepeloton.com", category: "Fitness", defaultCycle: .monthly,
                cancellationURL: "https://members.onepeloton.com/membership"),
        Service(names: ["Strava", "Strava Premium"], domain: "strava.com", category: "Fitness", defaultCycle: .monthly,
                cancellationURL: "https://www.strava.com/settings/billing"),
        Service(names: ["MyFitnessPal", "MyFitnessPal Premium"], domain: "myfitnesspal.com", category: "Fitness", defaultCycle: .monthly,
                cancellationURL: "https://www.myfitnesspal.com/account/change_subscription"),
        Service(names: ["Headspace", "Headspace Plus"], domain: "headspace.com", category: "Fitness", defaultCycle: .yearly,
                cancellationURL: "https://my.headspace.com/subscription/manage"),
        Service(names: ["Calm", "Calm Premium"], domain: "calm.com", category: "Fitness", defaultCycle: .yearly,
                cancellationURL: "https://app.www.calm.com/profile/subscription"),
        Service(names: ["Keep", "Keep Premium"], domain: "keep.com", category: "Fitness", defaultCycle: .monthly,
                cancellationURL: nil),

        // Finance
        Service(names: ["Robinhood", "Robinhood Gold"], domain: "robinhood.com", category: "Finance", defaultCycle: .monthly,
                cancellationURL: "https://robinhood.com/account/settings"),
        Service(names: ["Revolut", "Revolut Premium", "Revolut Metal"], domain: "revolut.com", category: "Finance", defaultCycle: .monthly,
                cancellationURL: nil),
        Service(names: ["YNAB", "You Need A Budget"], domain: "ynab.com", category: "Finance", defaultCycle: .yearly,
                cancellationURL: "https://app.ynab.com/settings/billing"),
        Service(names: ["Mint", "Mint Premium"], domain: "mint.com", category: "Finance", defaultCycle: .monthly,
                cancellationURL: "https://mint.intuit.com/settings.event"),

        // VPN & Security
        Service(names: ["NordVPN", "Nord VPN"], domain: "nordvpn.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://my.nordaccount.com/dashboard/nordvpn/"),
        Service(names: ["ExpressVPN", "Express VPN"], domain: "expressvpn.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://www.expressvpn.com/subscriptions"),
        Service(names: ["Surfshark", "SurfShark"], domain: "surfshark.com", category: "Software", defaultCycle: .yearly,
                cancellationURL: "https://my.surfshark.com/account/overview"),

        // Developer / Cloud
        Service(names: ["GitHub", "GitHub Pro", "GitHub Team"], domain: "github.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://github.com/settings/billing/summary"),
        Service(names: ["GitLab", "GitLab Premium"], domain: "gitlab.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://gitlab.com/-/profile/billings"),
        Service(names: ["Vercel", "Vercel Pro"], domain: "vercel.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://vercel.com/dashboard/settings/billing"),
        Service(names: ["Netlify", "Netlify Pro"], domain: "netlify.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://app.netlify.com/teams/billing"),
        Service(names: ["AWS", "Amazon Web Services"], domain: "aws.amazon.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://console.aws.amazon.com/billing/home"),
        Service(names: ["Heroku", "Heroku Pro"], domain: "heroku.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://dashboard.heroku.com/account/billing"),
        Service(names: ["DigitalOcean", "Digital Ocean"], domain: "digitalocean.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://cloud.digitalocean.com/account/billing"),
        Service(names: ["Cloudflare", "Cloudflare Pro"], domain: "cloudflare.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://dash.cloudflare.com/?to=/:account/billing"),

        // Design
        Service(names: ["Sketch", "Sketch Pro"], domain: "sketch.com", category: "Productivity", defaultCycle: .yearly,
                cancellationURL: "https://www.sketch.com/workspace/billing/"),
        Service(names: ["Framer", "Framer Pro"], domain: "framer.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://www.framer.com/account"),
        Service(names: ["InVision", "Invision"], domain: "invisionapp.com", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: nil),

        // Communication
        Service(names: ["Zoom", "Zoom Pro", "Zoom Workplace"], domain: "zoom.us", category: "Productivity", defaultCycle: .monthly,
                cancellationURL: "https://zoom.us/billing"),
        Service(names: ["Discord", "Discord Nitro", "Nitro"], domain: "discord.com", category: "Software", defaultCycle: .monthly,
                cancellationURL: "https://discord.com/settings/subscriptions"),
        Service(names: ["Telegram", "Telegram Premium"], domain: "telegram.org", category: "Software", defaultCycle: .monthly,
                cancellationURL: appleSubscriptionsURL),
    ]

    // MARK: - Matching

    /// Find the best matching known service in the given text.
    /// Prefers longer name matches (e.g. "YouTube Premium" over "YouTube").
    static func findMatch(in text: String) -> Service? {
        let lowerText = text.lowercased()
        var bestMatch: Service?
        var bestLength = 0

        for service in all {
            for name in service.names {
                let lowerName = name.lowercased()
                if lowerText.contains(lowerName) && name.count > bestLength {
                    bestMatch = service
                    bestLength = name.count
                }
            }
        }

        return bestMatch
    }

    /// v1.6 One-Tap Cancel lookup. Returns the service's cancel URL if known,
    /// or nil (caller should fall back to DuckDuckGo search via OneTapCancelService).
    static func cancellationURL(for subscriptionName: String) -> String? {
        findMatch(in: subscriptionName)?.cancellationURL
    }
}
