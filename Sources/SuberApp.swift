import SwiftUI

@main
struct SuberApp: App {
    init() {
        // v1.8.0: rescue v1.6.0/v1.6.1 → v1.7.x upgraders' data from the
        // legacy app-group plist (cfprefsd path that v1.6.2 abandoned).
        // Must run BEFORE StorageService.shared.loadSettings() below or
        // the first read sees empty AppGroupStore. No-op on fresh installs
        // and on users who already migrated.
        LegacyDataMigration.runIfNeeded()

        // v1.6: apply the user's language override BEFORE any view loads.
        // Foundation caches NSBundle lookups very early; this needs to run
        // before the first @Published settings read or first Text() resolve.
        let saved = StorageService.shared.loadSettings().language
        let choice = LanguageOverride.Choice(rawValue: saved) ?? .system
        LanguageOverride.apply(choice)
    }

    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var settingsStore = SettingsStore()
    /// Drives the "Import" Window scene. Exposed to both the MenuBarExtra popover
    /// (to trigger imports) and the import window (to render the right flow).
    @StateObject private var importPresenter = ImportPresenter()
    /// v1.6 Watchdog — Mail scan state machine, daily scheduler, scan-cursor
    /// persistence. Wired to subscriptionStore via onScanComplete callback
    /// (set up in init so the closure captures the store reference once).
    @StateObject private var mailWatchdog = MailWatchdog()
    /// v1.8.0 OverlayPresenter — popover-root 弹窗协调器。深嵌触发的 modal
    /// （IMAPAccountSheet / AutopilotConsentSheet / CancelConfirmationSheet）
    /// 通过 present(...) 把内容推到 MenuBarView 根节点渲染，避免 v1.7.1
    /// 的 .popoverOverlay 在 section 边界内 inline 错位的问题。
    @StateObject private var overlayPresenter = OverlayPresenter()

    var body: some Scene {
        // v1.6: `label:` closure replaces the `image:` arg so we can overlay
        // the unread-changes badge. Plan-as-written uses the SwiftUI overlay
        // (MenuBarBadgeView); if notarized-build QA reveals template-mode
        // strips the red fill, swap to `MenuBarBadgeFallback.render(count:)`.
        MenuBarExtra {
            // Wrap in a View so we can access @Environment(\.openWindow) for
            // suber://changes URL routing (Slice 4h).
            MenuBarContainerView(
                subscriptionStore: subscriptionStore,
                settingsStore: settingsStore,
                importPresenter: importPresenter,
                mailWatchdog: mailWatchdog,
                overlayPresenter: overlayPresenter,
                setupCloudSync: setupCloudSync,
                setupWatchdog: setupWatchdog,
                rebuildBridge: { mailWatchdog.setBridge(buildBridge()) },
                handleURL: handleURL
            )
        } label: {
            MenuBarBadgeView(count: subscriptionStore.unreadChangeCount)
        }
        .menuBarExtraStyle(.window)
        .handlesExternalEvents(matching: ["suber"])

        // Separate Window for import flows. Running in a regular window scene
        // (instead of an overlay inside the MenuBarExtra popover) lets TCC
        // dialogs, file pickers, and system notifications stack above it
        // correctly — fixes the "popover blocks everything" bug in v1.5.1.
        Window("Import Subscriptions", id: "import") {
            ImportWindowView()
                .environmentObject(subscriptionStore)
                .environmentObject(settingsStore)
                .environmentObject(importPresenter)
                .environmentObject(mailWatchdog)
        }
        .defaultSize(width: 620, height: 620)
        .windowResizability(.contentMinSize)
    }

    // MARK: - Watchdog wiring (v1.6 Sentinel loop)

    /// Build the active bridge from current settings. v1.7 IMAP support:
    /// composes [AppleMailBridge?, GenericIMAPBridge?] into a CompositeMailBridge
    /// so MailWatchdog sees ONE bridge regardless of how many sources the
    /// user has configured. Apple Mail is always included (Watch toggle
    /// gates whether scans actually use it inside ChangeDetector flow);
    /// GenericIMAPBridge is added only if the user configured an IMAP
    /// account in Settings → Autopilot.
    private func buildBridge() -> MailBridge {
        var bridges: [MailBridge] = [AppleMailBridge()]
        if let account = settingsStore.settings.autopilot.imapAccount {
            bridges.append(GenericIMAPBridge(account: account))
        }
        return bridges.count == 1 ? bridges[0] : CompositeMailBridge(bridges: bridges)
    }

    /// Called from MenuBarContainerView.onAppear (once per app launch).
    /// Wires the onScanComplete callback so scans route through the Sentinel
    /// loop: recordAndPersist (dedup + prune) → grouped notification → badge.
    /// Also restarts the daily scheduler if Watch is enabled.
    private func setupWatchdog() {
        // v1.7 IMAP: build the initial bridge composition from settings.
        // Subscribe to settings changes to rebuild whenever the user adds
        // or removes an IMAP account (so the swap takes effect without
        // an app restart).
        mailWatchdog.setBridge(buildBridge())
        // The callback captures subscriptionStore + settings by reference.
        // Runs on MainActor because MailWatchdog is MainActor-isolated.
        mailWatchdog.loadExistingSubscriptions = { [weak subscriptionStore] in
            subscriptionStore?.subscriptions ?? []
        }
        mailWatchdog.onScanComplete = { [weak subscriptionStore, weak settingsStore] summary, changes in
            guard let store = subscriptionStore, let settings = settingsStore else { return }

            // Filter changes by user's alert preferences (D6).
            let filtered = changes.filter { change in
                switch change.type {
                case .priceChange:
                    return settings.settings.autopilot.alertOnPriceChanges
                case .newCharge:
                    return settings.settings.autopilot.alertOnNewSubscriptions
                case .duplicate:
                    return settings.settings.autopilot.alertOnDuplicates
                // Trials + cancellation-related changes always surface
                // (they're actionable regardless of alert prefs).
                case .trialExpiring, .cancellationConfirmed, .cancellationFailed:
                    return true
                }
            }

            // Dedup + prune + persist.
            store.recordAndPersist(changes: filtered)

            // Fire a single grouped notification if there's anything to say.
            if !filtered.isEmpty, settings.settings.enableNotifications {
                let (title, body) = NotificationService.composeChangesBody(from: filtered)
                NotificationService.shared.scheduleImmediate(title: title, body: body)
            }

            // P1 (eng re-review): fold auto-transition check into scan-completion.
            // The Watchdog scan IS the data source that covers the window for
            // users with Watchdog enabled. We don't have StatementTransaction
            // here (Watchdog yields SubscriptionChange), so we synthesize a
            // "transactions" view by reading the .newCharge + .priceChange
            // candidates' pendingSubscriptionData — each one represents a real
            // incoming charge the bridge saw.
            let syntheticTxns = filtered.compactMap { change -> StatementTransaction? in
                // Only .priceChange and .newCharge represent real seen charges.
                guard change.type == .priceChange || change.type == .newCharge else { return nil }
                guard let form = change.pendingSubscriptionData,
                      let amount = Double(form.amount) else { return nil }
                return StatementTransaction(
                    date: change.detectedAt,
                    merchantRaw: form.name,
                    amount: amount,
                    currency: form.currency
                )
            }
            store.checkPendingCancellationTransitions(
                transactions: syntheticTxns,
                dataSourceCoversWindow: true,   // Watchdog ran → window covered
                now: summary.completedAt
            )
        }

        // Resume the daily scheduler if Watch is enabled.
        if settingsStore.settings.autopilot.watchAppleMail {
            mailWatchdog.scheduleDailyScan()
        }
    }

    /// `openWindow` is a SwiftUI Environment value and must be captured inside
    /// a View — the caller (MenuBarContainerView) passes it through.
    private func handleURL(_ url: URL, openWindow: OpenWindowAction) {
        guard let action = URLSchemeHandler.parseAction(url) else { return }
        switch action {
        case .add(let data):
            subscriptionStore.add(data)
        case .openChanges:
            // v1.6 Sentinel: route from menubar badge / grouped notification /
            // "Since you were away" banner straight to the Changes Window.
            // Snapshot the current unread log so the Window opens with data.
            importPresenter.showChanges(subscriptionStore.changes)
            WindowActivationCoordinator.surface()
            openWindow(id: "import")
        }
    }

    private func setupCloudSync() {
        guard settingsStore.settings.enableCloudSync else { return }

        CloudSyncService.shared.startSync()

        CloudSyncService.shared.onRemoteChange = { [weak subscriptionStore, weak settingsStore] subsData, settingsData, changesData in
            if let data = subsData,
               let subs = try? JSONDecoder.suberDecoder.decode([Subscription].self, from: data) {
                subscriptionStore?.importSubscriptions(subs)
            }
            if let data = settingsData,
               let settings = try? JSONDecoder.suberDecoder.decode(AppSettings.self, from: data) {
                settingsStore?.update { $0 = settings }
            }
            // v1.6: SubscriptionChange log sync. Merge-by-id with local log;
            // the dedup hash in SubscriptionStore.recordAndPersist handles
            // cross-device duplicates (same change detected on 2 Macs).
            if let data = changesData,
               let remoteChanges = try? JSONDecoder.suberDecoder.decode([SubscriptionChange].self, from: data) {
                subscriptionStore?.mergeRemoteChanges(remoteChanges)
            }
        }
    }
}

// MARK: - Shared Decoder

extension JSONDecoder {
    /// Shared decoder matching StorageService's date handling.
    static let suberDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFractional.date(from: str) { return date }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }

            let dateOnly = DateFormatter()
            dateOnly.dateFormat = "yyyy-MM-dd"
            dateOnly.locale = Locale(identifier: "en_US_POSIX")
            dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = dateOnly.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()
}

// MARK: - MenuBar container

/// Thin wrapper so the MenuBarExtra content has access to SwiftUI Environment
/// values (notably `openWindow` for URL-scheme routing to the Changes Window).
/// Can't live on the App type directly; Environment values only bind inside
/// View hierarchies.
private struct MenuBarContainerView: View {
    let subscriptionStore: SubscriptionStore
    let settingsStore: SettingsStore
    let importPresenter: ImportPresenter
    let mailWatchdog: MailWatchdog
    /// v1.8.0: popover-root overlay coordinator (see OverlayPresenter docs).
    let overlayPresenter: OverlayPresenter
    let setupCloudSync: () -> Void
    let setupWatchdog: () -> Void
    /// v1.7 IMAP: rebuilds the MailBridge composition when settings change.
    /// Called from .onReceive when imapAccount adds/removes; passes the new
    /// bridge to MailWatchdog.setBridge() so the next scan picks it up.
    let rebuildBridge: () -> Void
    let handleURL: (URL, OpenWindowAction) -> Void

    @Environment(\.openWindow) private var openWindow
    /// Track the previous imapAccount so we only rebuild on actual transitions
    /// (not every settings tweak).
    @State private var lastIMAPAccountID: String?

    var body: some View {
        MenuBarView()
            .environmentObject(subscriptionStore)
            .environmentObject(settingsStore)
            .environmentObject(importPresenter)
            .environmentObject(mailWatchdog)
            .environmentObject(overlayPresenter)
            .frame(width: 480)
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.bgPrimary)
            .onAppear {
                setupCloudSync()
                setupWatchdog()
                lastIMAPAccountID = settingsStore.settings.autopilot.imapAccount?.id
                Task { await ExchangeRateService.shared.refreshIfNeeded() }
                // v1.8.0: start Sparkle background updater (in-app auto-update).
                // Deferred to onAppear so other launch-time work (LegacyDataMigration,
                // CloudSync) runs first and so Sparkle isn't racing with first-
                // launch Gatekeeper / quarantine processing.
                UpdateService.shared.start()
            }
            .onOpenURL { url in handleURL(url, openWindow) }
            .onReceive(settingsStore.$settings) { settings in
                if settings.enableCloudSync {
                    CloudSyncService.shared.startSync()
                } else {
                    CloudSyncService.shared.stopSync()
                }
                // v1.7: rebuild the MailBridge composition if the IMAP
                // account membership changed (added, removed, or swapped
                // for a different one).
                let newID = settings.autopilot.imapAccount?.id
                if newID != lastIMAPAccountID {
                    lastIMAPAccountID = newID
                    rebuildBridge()
                }
            }
    }
}
