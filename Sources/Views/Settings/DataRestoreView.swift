import SwiftUI

// ┌────────────── DataRestoreView — Settings → Data → Restore (v1.9.0) ────────┐
// │                                                                            │
// │  The user-facing replacement for the disabled LegacyDataMigration.         │
// │  Lists every backup source (`RestoreSourceLister`) and lets the user      │
// │  explicitly choose one to restore from. Three sources can show up:        │
// │                                                                            │
// │    📅  Local backup · 12 minutes ago        — DataBackupManager rotating   │
// │    ☁️   iCloud · 9 subscriptions             — KVS pull (sync must be on)   │
// │    📦  Legacy data (v1.6.x) · 9 subs        — pre-v1.6.2 group plist       │
// │                                                                            │
// │  Restore flow:                                                             │
// │    1. User taps [Restore] on a row.                                        │
// │    2. Confirmation dialog: "This will replace your current X subs with    │
// │       this backup's Y subs. Continue?"                                     │
// │    3. On confirm:                                                          │
// │       a. Decode subscriptions from `BackupSource.subscriptionsData`.       │
// │       b. SubscriptionStore.replaceAll(..., reason: .userRestore) — writes  │
// │          through AppGroupStore.set, which takes a fresh snapshot via       │
// │          DataBackupManager. So even an unintended restore is recoverable.  │
// │       c. Optionally restore settings + change log if the source has them. │
// │                                                                            │
// │  Presentation: rendered via OverlayPresenter (popover-root) so the       │
// │  confirmation dialog isn't blown away by SecureField focus / popover     │
// │  re-keying — same lesson as v1.7.1 / v1.8.0.                              │
// │                                                                            │
// └────────────────────────────────────────────────────────────────────────────┘

struct DataRestoreView: View {
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var overlayPresenter: OverlayPresenter

    /// Caller (SettingsView) flips this to dismiss the overlay.
    let onClose: () -> Void

    @State private var sources: [BackupSource] = []
    @State private var pendingSource: BackupSource?
    @State private var showConfirm = false
    @State private var restoreSummary: String?  // success toast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("Restore from Backup")
                    .font(AppFont.bold(16))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Theme.border)

            // Body — scrollable list of sources
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if sources.isEmpty {
                        emptyState
                    } else {
                        Text("Available backups, newest first:")
                            .font(AppFont.regular(11))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.bottom, 4)

                        ForEach(sources) { source in
                            sourceRow(source)
                        }
                    }

                    if let summary = restoreSummary {
                        successBanner(summary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear { reload() }
        .alert("Restore this backup?",
               isPresented: $showConfirm,
               presenting: pendingSource) { source in
            Button("Restore", role: .destructive) {
                performRestore(source)
            }
            Button("Cancel", role: .cancel) {
                pendingSource = nil
            }
        } message: { source in
            // Honest copy: explicitly name what's being replaced + with what.
            Text("This will replace your current \(subscriptionStore.subscriptions.count) subscriptions "
                 + "with this backup's \(source.subscriptionCount) subscriptions. "
                 + "Your current data will be saved as a new local backup automatically.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(Theme.textDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No backups found")
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                    Text("Local backups are created automatically when subscriptions are saved. " +
                         "iCloud backups require iCloud sync to be on.")
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.bgCell)
            )
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: BackupSource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            kindIcon(source.kind)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.label)
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                Text(detailLine(for: source))
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button(action: {
                pendingSource = source
                showConfirm = true
            }) {
                Text("Restore")
                    .font(AppFont.medium(12))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.bgCell)
        )
    }

    @ViewBuilder
    private func kindIcon(_ kind: BackupSource.Kind) -> some View {
        switch kind {
        case .localRotating:
            Image(systemName: "internaldrive")
                .font(.system(size: 18))
                .foregroundColor(Theme.accent)
        case .iCloudKVS:
            Image(systemName: "icloud")
                .font(.system(size: 18))
                .foregroundColor(Theme.accent)
        case .legacyPlist:
            Image(systemName: "archivebox")
                .font(.system(size: 18))
                .foregroundColor(Theme.warning)
        }
    }

    private func detailLine(for source: BackupSource) -> String {
        let count = source.subscriptionCount
        let subs = "\(count) subscription\(count == 1 ? "" : "s")"
        var pieces: [String] = [subs]
        if source.settingsData != nil {
            pieces.append("settings included")
        }
        if source.changesData != nil {
            pieces.append("change log included")
        }
        return pieces.joined(separator: " · ")
    }

    @ViewBuilder
    private func successBanner(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.success)
            Text(summary)
                .font(AppFont.regular(12))
                .foregroundColor(Theme.textPrimary)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.success.opacity(0.15))
        )
    }

    // MARK: - Actions

    private func reload() {
        sources = RestoreSourceLister.listAvailableSources(
            iCloudSyncEnabled: settingsStore.settings.enableCloudSync
        )
    }

    private func performRestore(_ source: BackupSource) {
        // Decode subscriptions from the backup blob. Failure here (corrupt
        // file, schema drift) leaves the live store untouched — we surface
        // the error and let the user pick another source.
        guard let subs = try? JSONDecoder.suberDecoder
            .decode([Subscription].self, from: source.subscriptionsData) else {
            restoreSummary = "Couldn't read this backup — try another source."
            return
        }

        // 1) Subscriptions — this is the critical payload.
        // replaceAll snapshots the outgoing list to Backups/ before overwriting
        // (and save() → AppGroupStore.set snapshots the new list too), so the
        // old live data automatically becomes another rotating backup.
        // That makes Restore itself reversible: bad pick → restore an even
        // older snapshot to revert.
        subscriptionStore.replaceAll(subs, reason: .userRestore)

        // 2) Settings — best-effort. Decode failure just skips this part;
        // user keeps their current settings rather than getting a broken set.
        if let settingsData = source.settingsData,
           let settings = try? JSONDecoder.suberDecoder
            .decode(AppSettings.self, from: settingsData) {
            settingsStore.update { $0 = settings }
        }

        // 3) Change log — best-effort. Same pattern.
        if let changesData = source.changesData,
           let changes = try? JSONDecoder.suberDecoder
            .decode([SubscriptionChange].self, from: changesData) {
            subscriptionStore.changes = changes
            StorageService.shared.saveChanges(changes)
        }

        restoreSummary = "Restored \(subs.count) subscription\(subs.count == 1 ? "" : "s") from \(source.label)."
        pendingSource = nil
        // Don't auto-close — let the user see the success banner and review.
        // They can close manually via the X button.
        // v1.9.2: the restore wrote new data + created a fresh backup, so the
        // available-sources list is now stale — refresh it.
        reload()
    }
}
