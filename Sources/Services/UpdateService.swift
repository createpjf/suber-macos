import Foundation
import Sparkle

// ┌───────────── UpdateService — v1.8.0 Sparkle 2 wrapper ─────────────────────┐
// │                                                                            │
// │  v1.7.x and earlier: hand-rolled GitHub Releases API check + download DMG  │
// │  to ~/Downloads + NSWorkspace.shared.open(dmgURL) → user manually drags    │
// │  Suber.app over /Applications. macOS Sequoia/Tahoe added App Management    │
// │  TCC prompt to that flow, making it even worse.                            │
// │                                                                            │
// │  v1.8.0: Sparkle 2 handles the whole pipeline:                             │
// │    - Periodic + on-demand appcast fetch (signed with EdDSA)                │
// │    - User-facing "update available" UI (built-in Sparkle dialog)           │
// │    - Download + verify EdDSA signature (private key in our Keychain;       │
// │      public key embedded in Info.plist as SUPublicEDKey)                   │
// │    - Atomic swap of /Applications/Suber.app via signed XPC helper          │
// │      (SUEnableInstallerLauncherService=true) — bypasses macOS Tahoe's      │
// │      App Management TCC prompt that we'd hit if we DIY'd                   │
// │    - Quit + relaunch with new binary                                       │
// │                                                                            │
// │  Settings UI: just expose checkForUpdates() + automaticallyChecks toggle.  │
// │  Sparkle's built-in dialogs handle the actual update prompt UX.            │
// │                                                                            │
// │  Feed config (in Sources/Info.plist):                                      │
// │    SUFeedURL                = https://github.com/createpjf/suber-macos/    │
// │                                releases/latest/download/appcast.xml        │
// │    SUPublicEDKey            = <base64 EdDSA public key>                    │
// │    SUEnableInstallerLauncherService = true                                 │
// │                                                                            │
// │  Build pipeline: scripts/build-dmg.sh step [9/10] runs generate_appcast    │
// │  to sign each new DMG and upload appcast.xml as a release asset alongside  │
// │  the DMG. The "latest/download/appcast.xml" URL auto-redirects.            │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    private let updaterController: SPUStandardUpdaterController

    /// Reflects Sparkle's own canCheckForUpdates flag — true except briefly
    /// while a check is in progress. Settings button uses this for disable.
    @Published private(set) var canCheckForUpdates: Bool = true

    /// Last time Sparkle actually attempted an update check. Surfaced in
    /// Settings → Updates as "Last checked: …" so users see the cadence.
    @Published private(set) var lastCheckedAt: Date?

    private override init() {
        // startingUpdater: false — defer to SuberApp's onAppear so we can
        // control timing relative to other launch-time work (LegacyDataMigration,
        // CloudSync, etc.). Calling start() too early can race against macOS's
        // first-launch quarantine release.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Start the Sparkle background updater. Called once at app launch from
    /// MenuBarContainerView.onAppear.
    func start() {
        updaterController.startUpdater()
        // Wire @Published mirrors so SwiftUI views reactively update.
        // Sparkle's Updater is KVO-compliant on these keys.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        updaterController.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastCheckedAt)
    }

    /// User tapped "Check for updates" in Settings → Updates. Sparkle handles
    /// the rest (no-update-available alert / update prompt with release notes /
    /// download progress / install + relaunch).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Settings toggle. Sparkle persists this to UserDefaults (own bundle,
    /// no app-group quirks).
    var automaticallyChecks: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Bundle marketing version — surfaced in Settings → About + Updates.
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
