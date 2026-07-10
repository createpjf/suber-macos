import SwiftUI
import UniformTypeIdentifiers

/// Top-level flow for importing a bank / pay-platform statement CSV.
///
/// Flow stages:
/// 1. `.formatPicker` — choose Alipay / WeChat / Generic
/// 2. `.dropZone` — drop or pick the CSV file
/// 3. `.processing` — parse + detect (usually <1s)
/// 4. `.review` — hand off to `ImportReviewListView` with detected candidates
/// 5. `.error` — show a friendly error with a retry button
struct BankImportView: View {
    let existingSubscriptions: [Subscription]
    let onAdd: ([SubscriptionFormData]) -> Void
    let onCancel: () -> Void

    enum Stage {
        case formatPicker
        case dropZone(StatementFormat)
        case processing
        case review([CandidateSubscription], StatementFormat)
        case error(String, StatementFormat?)
    }

    @State private var stage: Stage = .formatPicker

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)

            switch stage {
            case .formatPicker:
                formatPicker
            case .dropZone(let format):
                dropZone(for: format)
            case .processing:
                processingView
            case .review(let candidates, _):
                ImportReviewListView(
                    candidates: candidates,
                    existingSubscriptions: existingSubscriptions,
                    onAdd: onAdd,
                    onCancel: onCancel
                )
            case .error(let msg, let format):
                errorView(msg, format: format)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgPrimary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if case .dropZone = stage {
                Button(action: { stage = .formatPicker }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.bgCell)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                // AUDIT-v1.9.2 U-10: icon-only back/close buttons need labels.
                .accessibilityLabel(Text("Back"))
                .help("Back")
            }

            Text(headerTitle)
                .font(AppFont.medium(15))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.bgCell)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var headerTitle: String {
        // AUDIT-v1.9.2 U-03: String(localized:) — this computed String feeds
        // Text(headerTitle), which renders verbatim without explicit lookup.
        switch stage {
        case .formatPicker, .error: return String(localized: "Import bank statement")
        case .dropZone(let f): return f.displayName
        case .processing: return String(localized: "Scanning for subscriptions…")
        case .review: return String(localized: "Review detected subscriptions")
        }
    }

    // MARK: - Format picker

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your statement source")
                .font(AppFont.medium(13))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 8)

            VStack(spacing: 10) {
                formatButton(AlipayFormat())
                formatButton(WechatFormat())
                formatButton(GenericFormat())
            }

            Spacer()

            privacyNote
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func formatButton(_ format: StatementFormat) -> some View {
        Button(action: { stage = .dropZone(format) }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                    Text(format.subtitle)
                        .font(AppFont.regular(11))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
            Text("Everything runs locally. No file leaves your Mac.")
                .font(AppFont.regular(11))
        }
        .foregroundColor(Theme.textDim)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Drop zone

    @State private var isTargeted = false

    private func dropZone(for format: StatementFormat) -> some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(isTargeted ? Theme.textPrimary : Theme.textDim)
                Text("Drop your \(format.displayName) CSV here")
                    .font(AppFont.regular(13))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargeted ? Theme.textPrimary : Theme.textDim,
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Theme.bgCell.opacity(0.5) : Color.clear)
            )
            .onDrop(of: [.fileURL, .commaSeparatedText, .plainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers, format: format)
                return true
            }
            .padding(.horizontal, 20)

            HStack {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("or")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textDim)
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .padding(.horizontal, 40)

            Button(action: { openFilePicker(format: format) }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text("Choose CSV file")
                        .font(AppFont.medium(13))
                }
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Theme.bgCell)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            privacyNote
                .padding(.bottom, 16)
        }
    }

    // MARK: - Processing / Error

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Scanning for recurring charges…")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String, format: StatementFormat?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.warning)
            Text(message)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button(action: { stage = .formatPicker }) {
                    Text("Pick a different format")
                        .font(AppFont.medium(13))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.bgCell)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                if let f = format {
                    Button(action: { stage = .dropZone(f) }) {
                        Text("Try again")
                            .font(AppFont.medium(13))
                            .foregroundColor(Theme.bgPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    // MARK: - Import actions

    private func handleDrop(_ providers: [NSItemProvider], format: StatementFormat) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    processFile(at: url, format: format)
                }
            }
            return
        }
    }

    private func openFilePicker(format: StatementFormat) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Select a CSV statement file")

        if panel.runModal() == .OK, let url = panel.url {
            processFile(at: url, format: format)
        }
    }

    private func processFile(at url: URL, format: StatementFormat) {
        stage = .processing

        // AUDIT-v1.9.2 C-22: View is @MainActor, so a plain `Task {}` inherits
        // main-actor isolation — the synchronous Data(contentsOf:) + CSV parse
        // would freeze the whole UI on large statements. Detach so the heavy
        // work runs off-main; hop back to main only for `stage` updates.
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let text = try CSVParser.decode(data)
                let rows = CSVParser.parse(text)
                let transactions = try format.parse(rows: rows)
                let candidates = RecurringChargeDetector.detect(transactions: transactions)

                await MainActor.run {
                    if candidates.isEmpty {
                        stage = .error(
                            String(localized: "Found \(transactions.count) transactions but no recurring charges. Make sure the CSV covers at least 2 months."),
                            format
                        )
                    } else {
                        stage = .review(candidates, format)
                    }
                }
            } catch {
                await MainActor.run {
                    stage = .error(error.localizedDescription, format)
                }
            }
        }
    }
}
