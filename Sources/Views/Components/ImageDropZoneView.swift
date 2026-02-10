import SwiftUI
import UniformTypeIdentifiers

/// Image input view supporting drag-and-drop, clipboard paste, and file picker.
struct ImageDropZoneView: View {
    let onResult: (SubscriptionTextParser.ParsedSubscription) -> Void
    let onCancel: () -> Void

    @State private var isProcessing = false
    @State private var isTargeted = false
    @State private var previewImage: NSImage?
    @State private var errorMessage: String?
    @State private var resultSummary: String?
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Scan subscription")
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
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Main content area
            if isProcessing {
                processingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let summary = resultSummary {
                successView(summary)
            } else {
                dropZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgPrimary)
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            // Drop area
            VStack(spacing: 12) {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(isTargeted ? Theme.textPrimary : Theme.textDim)

                    Text("Drop image here or ⌘V to paste")
                        .font(AppFont.regular(13))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160)
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
            .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .padding(.horizontal, 20)

            // Or divider
            HStack {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text("or")
                    .font(AppFont.regular(11))
                    .foregroundColor(Theme.textDim)
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .padding(.horizontal, 40)

            // Choose file button
            Button(action: openFilePicker) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text("Choose image file")
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

            // Paste hint
            Text("Tip: Screenshot a billing email, then ⌘V here")
                .font(AppFont.regular(11))
                .foregroundColor(Theme.textDim)
                .padding(.bottom, 16)
        }
        .onAppear {
            pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.characters == "v" {
                    handlePaste()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = pasteMonitor {
                NSEvent.removeMonitor(monitor)
                pasteMonitor = nil
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Recognizing text...")
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textSecondary)

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(0.6)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
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

            Button(action: reset) {
                Text("Try again")
                    .font(AppFont.medium(13))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Theme.bgCell)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Success View

    private func successView(_ summary: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.success)
            Text(summary)
                .font(AppFont.regular(13))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // Try image data first
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage {
                        DispatchQueue.main.async {
                            processImage(image)
                        }
                    }
                }
                return
            }

            // Try file URL
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    processImage(image)
                }
            }
        }
    }

    private func handlePaste() {
        guard let items = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil),
              let image = items.first as? NSImage else {
            errorMessage = "No image found on clipboard.\nCopy a screenshot first (⌘⇧4)."
            return
        }
        processImage(image)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a subscription screenshot or receipt"

        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            processImage(image)
        }
    }

    private func processImage(_ image: NSImage) {
        previewImage = image
        isProcessing = true
        errorMessage = nil
        resultSummary = nil

        Task {
            do {
                let ocrResult = try await ImageRecognitionService.recognizeText(from: image)

                if ocrResult.isEmpty {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = "No text found in image.\nTry a clearer screenshot."
                    }
                    return
                }

                if ocrResult.averageConfidence < 0.3 {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = "Image quality is too low.\nTry a higher resolution screenshot."
                    }
                    return
                }

                let parsed = SubscriptionTextParser.parse(ocrResult.fullText)

                // Build summary
                var parts: [String] = []
                if let name = parsed.name { parts.append(name) }
                if let amount = parsed.amount {
                    let symbol = parsed.currency.flatMap { AppConstants.currencySymbols[$0] } ?? ""
                    let cycleStr = parsed.cycle?.shortLabel ?? ""
                    parts.append("\(symbol)\(amount)\(cycleStr)")
                }
                let summary = parts.isEmpty ? "Partial data recognized" : "Found: " + parts.joined(separator: ", ")

                await MainActor.run {
                    isProcessing = false
                    resultSummary = summary
                    onResult(parsed)
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func reset() {
        previewImage = nil
        errorMessage = nil
        resultSummary = nil
        isProcessing = false
    }
}
