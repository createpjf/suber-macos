import SwiftUI

/// Drives what the secondary "Import" window shows.
///
/// The secondary window exists so system dialogs (TCC / file picker / notifications)
/// aren't occluded by the MenuBarExtra popover — popovers have a higher window
/// level than modal alerts. A regular `Window` scene behaves like any app window
/// and lets macOS sort z-order correctly.
///
/// MenuBarView writes to this object (from Settings button, Dashboard empty-state
/// CTA, or when the add form's OCR returns >1 subscription) and then calls
/// `openWindow(id: "import")`. ImportWindowView reads `mode` and renders the
/// corresponding flow.
@MainActor
final class ImportPresenter: ObservableObject {
    enum Mode: Equatable {
        case idle
        /// User chose to import from a bank / pay-platform statement CSV.
        case bankStatement
        /// User dropped a screenshot that OCR'd into N subscriptions.
        case reviewCandidates([CandidateSubscription])
    }

    @Published var mode: Mode = .idle

    /// Called by MenuBarView before triggering the Window open. Populates the
    /// presenter then signals the caller to `openWindow(id: "import")`.
    func showBankStatement() {
        mode = .bankStatement
    }

    func showCandidates(_ candidates: [CandidateSubscription]) {
        mode = .reviewCandidates(candidates)
    }

    func reset() {
        mode = .idle
    }
}
