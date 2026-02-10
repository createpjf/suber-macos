import Foundation

/// Database of well-known subscription services for OCR text matching.
enum KnownServices {
    struct Service {
        let names: [String]           // name variants (case-insensitive matching)
        let domain: String            // primary domain
        let category: String          // maps to AppConstants.categories
        let defaultCycle: BillingCycle
    }

    // MARK: - Database

    static let all: [Service] = [
        // Streaming
        Service(names: ["Netflix", "NETFLIX"], domain: "netflix.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Disney+", "Disney Plus", "DISNEY+"], domain: "disneyplus.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Hulu", "HULU"], domain: "hulu.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["HBO Max", "HBO", "Max"], domain: "max.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Amazon Prime", "Prime Video", "Amazon Prime Video"], domain: "amazon.com", category: "Streaming", defaultCycle: .yearly),
        Service(names: ["Apple TV+", "Apple TV Plus"], domain: "tv.apple.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Paramount+", "Paramount Plus"], domain: "paramountplus.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Peacock", "Peacock Premium"], domain: "peacocktv.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Crunchyroll", "CRUNCHYROLL"], domain: "crunchyroll.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["YouTube Premium", "YouTube Music", "YouTube TV"], domain: "youtube.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["Twitch", "Twitch Turbo"], domain: "twitch.tv", category: "Streaming", defaultCycle: .monthly),

        // Chinese Streaming
        Service(names: ["爱奇艺", "iQIYI", "iQiyi", "IQIYI"], domain: "iqiyi.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["腾讯视频", "Tencent Video"], domain: "v.qq.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["优酷", "Youku", "YOUKU"], domain: "youku.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["芒果TV", "MangoTV"], domain: "mgtv.com", category: "Streaming", defaultCycle: .monthly),
        Service(names: ["哔哩哔哩", "bilibili", "B站", "Bilibili"], domain: "bilibili.com", category: "Streaming", defaultCycle: .monthly),

        // Music
        Service(names: ["Spotify", "SPOTIFY", "Spotify Premium"], domain: "spotify.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["Apple Music"], domain: "music.apple.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["Tidal", "TIDAL"], domain: "tidal.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["Deezer", "DEEZER"], domain: "deezer.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["网易云音乐", "NetEase Music", "NetEase Cloud Music"], domain: "music.163.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["QQ音乐", "QQ Music"], domain: "y.qq.com", category: "Music", defaultCycle: .monthly),
        Service(names: ["SoundCloud", "SoundCloud Go"], domain: "soundcloud.com", category: "Music", defaultCycle: .monthly),

        // AI
        Service(names: ["ChatGPT", "ChatGPT Plus", "OpenAI"], domain: "openai.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["Claude", "Claude Pro", "Anthropic"], domain: "anthropic.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["Midjourney", "MidJourney", "MIDJOURNEY"], domain: "midjourney.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["GitHub Copilot", "Copilot"], domain: "github.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["Cursor", "Cursor Pro"], domain: "cursor.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["Perplexity", "Perplexity Pro"], domain: "perplexity.ai", category: "AI", defaultCycle: .monthly),
        Service(names: ["Gemini", "Google Gemini", "Gemini Advanced"], domain: "gemini.google.com", category: "AI", defaultCycle: .monthly),
        Service(names: ["Poe", "Poe Premium"], domain: "poe.com", category: "AI", defaultCycle: .monthly),

        // Software
        Service(names: ["Adobe", "Adobe Creative Cloud", "Creative Cloud", "Photoshop", "Lightroom", "Illustrator", "Premiere Pro"], domain: "adobe.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Microsoft 365", "Office 365", "Microsoft Office"], domain: "microsoft.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["JetBrains", "IntelliJ", "WebStorm", "PyCharm", "PhpStorm"], domain: "jetbrains.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["1Password", "1password"], domain: "1password.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["LastPass", "Lastpass"], domain: "lastpass.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["Dashlane"], domain: "dashlane.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["Setapp", "SETAPP"], domain: "setapp.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["CleanMyMac", "CleanMyMac X"], domain: "macpaw.com", category: "Software", defaultCycle: .yearly),

        // Cloud Storage
        Service(names: ["iCloud", "iCloud+", "Apple iCloud"], domain: "icloud.com", category: "Cloud Storage", defaultCycle: .monthly),
        Service(names: ["Google One", "Google Drive", "Google Storage"], domain: "one.google.com", category: "Cloud Storage", defaultCycle: .monthly),
        Service(names: ["Dropbox", "Dropbox Plus", "Dropbox Professional"], domain: "dropbox.com", category: "Cloud Storage", defaultCycle: .monthly),
        Service(names: ["OneDrive", "Microsoft OneDrive"], domain: "onedrive.com", category: "Cloud Storage", defaultCycle: .monthly),
        Service(names: ["Box", "Box.com"], domain: "box.com", category: "Cloud Storage", defaultCycle: .monthly),
        Service(names: ["百度网盘", "Baidu Pan", "百度云"], domain: "pan.baidu.com", category: "Cloud Storage", defaultCycle: .monthly),

        // Productivity
        Service(names: ["Notion", "NOTION", "Notion Plus", "Notion AI"], domain: "notion.so", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Figma", "FIGMA", "Figma Professional"], domain: "figma.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Slack", "SLACK", "Slack Pro"], domain: "slack.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Linear", "LINEAR"], domain: "linear.app", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Todoist", "Todoist Pro"], domain: "todoist.com", category: "Productivity", defaultCycle: .yearly),
        Service(names: ["Trello", "Trello Premium"], domain: "trello.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Asana", "Asana Premium"], domain: "asana.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Monday.com", "Monday"], domain: "monday.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Canva", "Canva Pro"], domain: "canva.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Miro", "Miro Board"], domain: "miro.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Evernote", "Evernote Premium"], domain: "evernote.com", category: "Productivity", defaultCycle: .yearly),
        Service(names: ["Bear", "Bear Pro"], domain: "bear.app", category: "Productivity", defaultCycle: .yearly),
        Service(names: ["Craft", "Craft Pro"], domain: "craft.do", category: "Productivity", defaultCycle: .yearly),

        // Education
        Service(names: ["Coursera", "Coursera Plus"], domain: "coursera.org", category: "Education", defaultCycle: .monthly),
        Service(names: ["Udemy"], domain: "udemy.com", category: "Education", defaultCycle: .oneTime),
        Service(names: ["Skillshare", "Skillshare Premium"], domain: "skillshare.com", category: "Education", defaultCycle: .yearly),
        Service(names: ["MasterClass", "Masterclass"], domain: "masterclass.com", category: "Education", defaultCycle: .yearly),
        Service(names: ["Duolingo", "Duolingo Plus", "Duolingo Super"], domain: "duolingo.com", category: "Education", defaultCycle: .monthly),
        Service(names: ["Brilliant", "Brilliant Premium"], domain: "brilliant.org", category: "Education", defaultCycle: .yearly),

        // News
        Service(names: ["The New York Times", "NYT", "NY Times", "New York Times"], domain: "nytimes.com", category: "News", defaultCycle: .monthly),
        Service(names: ["The Washington Post", "Washington Post"], domain: "washingtonpost.com", category: "News", defaultCycle: .monthly),
        Service(names: ["The Wall Street Journal", "WSJ", "Wall Street Journal"], domain: "wsj.com", category: "News", defaultCycle: .monthly),
        Service(names: ["The Economist", "Economist"], domain: "economist.com", category: "News", defaultCycle: .monthly),
        Service(names: ["Medium", "Medium Premium"], domain: "medium.com", category: "News", defaultCycle: .monthly),
        Service(names: ["Substack"], domain: "substack.com", category: "News", defaultCycle: .monthly),

        // Gaming
        Service(names: ["Xbox Game Pass", "Game Pass", "Xbox Live", "Xbox Gold"], domain: "xbox.com", category: "Gaming", defaultCycle: .monthly),
        Service(names: ["PlayStation Plus", "PS Plus", "PS+", "PlayStation Now"], domain: "playstation.com", category: "Gaming", defaultCycle: .monthly),
        Service(names: ["Nintendo Switch Online", "Nintendo Online"], domain: "nintendo.com", category: "Gaming", defaultCycle: .yearly),
        Service(names: ["Apple Arcade"], domain: "apple.com/apple-arcade", category: "Gaming", defaultCycle: .monthly),
        Service(names: ["EA Play", "EA Access"], domain: "ea.com", category: "Gaming", defaultCycle: .monthly),
        Service(names: ["Steam"], domain: "store.steampowered.com", category: "Gaming", defaultCycle: .oneTime),

        // Fitness
        Service(names: ["Apple Fitness+", "Apple Fitness Plus", "Fitness+"], domain: "apple.com/apple-fitness-plus", category: "Fitness", defaultCycle: .monthly),
        Service(names: ["Peloton", "Peloton Digital"], domain: "onepeloton.com", category: "Fitness", defaultCycle: .monthly),
        Service(names: ["Strava", "Strava Premium"], domain: "strava.com", category: "Fitness", defaultCycle: .monthly),
        Service(names: ["MyFitnessPal", "MyFitnessPal Premium"], domain: "myfitnesspal.com", category: "Fitness", defaultCycle: .monthly),
        Service(names: ["Headspace", "Headspace Plus"], domain: "headspace.com", category: "Fitness", defaultCycle: .yearly),
        Service(names: ["Calm", "Calm Premium"], domain: "calm.com", category: "Fitness", defaultCycle: .yearly),
        Service(names: ["Keep", "Keep Premium"], domain: "keep.com", category: "Fitness", defaultCycle: .monthly),

        // Finance
        Service(names: ["Robinhood", "Robinhood Gold"], domain: "robinhood.com", category: "Finance", defaultCycle: .monthly),
        Service(names: ["Revolut", "Revolut Premium", "Revolut Metal"], domain: "revolut.com", category: "Finance", defaultCycle: .monthly),
        Service(names: ["YNAB", "You Need A Budget"], domain: "ynab.com", category: "Finance", defaultCycle: .yearly),
        Service(names: ["Mint", "Mint Premium"], domain: "mint.com", category: "Finance", defaultCycle: .monthly),

        // VPN & Security
        Service(names: ["NordVPN", "Nord VPN"], domain: "nordvpn.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["ExpressVPN", "Express VPN"], domain: "expressvpn.com", category: "Software", defaultCycle: .yearly),
        Service(names: ["Surfshark", "SurfShark"], domain: "surfshark.com", category: "Software", defaultCycle: .yearly),

        // Developer / Cloud
        Service(names: ["GitHub", "GitHub Pro", "GitHub Team"], domain: "github.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["GitLab", "GitLab Premium"], domain: "gitlab.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Vercel", "Vercel Pro"], domain: "vercel.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Netlify", "Netlify Pro"], domain: "netlify.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["AWS", "Amazon Web Services"], domain: "aws.amazon.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Heroku", "Heroku Pro"], domain: "heroku.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["DigitalOcean", "Digital Ocean"], domain: "digitalocean.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Cloudflare", "Cloudflare Pro"], domain: "cloudflare.com", category: "Software", defaultCycle: .monthly),

        // Design
        Service(names: ["Sketch", "Sketch Pro"], domain: "sketch.com", category: "Productivity", defaultCycle: .yearly),
        Service(names: ["Framer", "Framer Pro"], domain: "framer.com", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["InVision", "Invision"], domain: "invisionapp.com", category: "Productivity", defaultCycle: .monthly),

        // Communication
        Service(names: ["Zoom", "Zoom Pro", "Zoom Workplace"], domain: "zoom.us", category: "Productivity", defaultCycle: .monthly),
        Service(names: ["Discord", "Discord Nitro", "Nitro"], domain: "discord.com", category: "Software", defaultCycle: .monthly),
        Service(names: ["Telegram", "Telegram Premium"], domain: "telegram.org", category: "Software", defaultCycle: .monthly),
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
}
