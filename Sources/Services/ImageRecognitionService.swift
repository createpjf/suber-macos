import Vision
import AppKit

/// Wraps Apple Vision framework for OCR text extraction from images.
enum ImageRecognitionService {

    struct RecognizedLine {
        let text: String
        let confidence: Float
    }

    struct RecognitionResult {
        let lines: [RecognizedLine]

        /// All recognized lines joined by newline.
        var fullText: String {
            lines.map(\.text).joined(separator: "\n")
        }

        var isEmpty: Bool { lines.isEmpty }

        /// Average confidence across all lines (0.0–1.0).
        var averageConfidence: Float {
            guard !lines.isEmpty else { return 0 }
            return lines.map(\.confidence).reduce(0, +) / Float(lines.count)
        }
    }

    enum RecognitionError: LocalizedError {
        case invalidImage
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not process the image."
            case .recognitionFailed(let msg):
                return "Text recognition failed: \(msg)"
            }
        }
    }

    // MARK: - Public API

    /// Recognize text from an NSImage using Apple Vision framework.
    /// - Parameters:
    ///   - image: The source image.
    ///   - languages: Recognition languages. Default: English + Chinese.
    /// - Returns: Recognized text result sorted top-to-bottom.
    static func recognizeText(
        from image: NSImage,
        languages: [String] = ["en", "zh-Hans", "zh-Hant"]
    ) async throws -> RecognitionResult {
        // Convert NSImage to CGImage
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Try via tiffRepresentation as fallback
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let cg = bitmap.cgImage else {
                throw RecognitionError.invalidImage
            }
            return try await performRecognition(on: cg, languages: languages)
        }
        return try await performRecognition(on: cgImage, languages: languages)
    }

    /// Recognize text from a file URL.
    static func recognizeText(
        from url: URL,
        languages: [String] = ["en", "zh-Hans", "zh-Hant"]
    ) async throws -> RecognitionResult {
        guard let image = NSImage(contentsOf: url) else {
            throw RecognitionError.invalidImage
        }
        return try await recognizeText(from: image, languages: languages)
    }

    /// Recognize text from clipboard image.
    static func recognizeTextFromClipboard(
        languages: [String] = ["en", "zh-Hans", "zh-Hant"]
    ) async throws -> RecognitionResult? {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return nil  // No image on clipboard
        }
        return try await recognizeText(from: image, languages: languages)
    }

    // MARK: - Private

    private static func performRecognition(
        on cgImage: CGImage,
        languages: [String]
    ) async throws -> RecognitionResult {
        // Downsample very large images to avoid memory issues
        let maxDimension = 4096
        let finalImage: CGImage
        if cgImage.width > maxDimension || cgImage.height > maxDimension {
            finalImage = downsample(cgImage, maxDimension: maxDimension) ?? cgImage
        } else {
            finalImage = cgImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: RecognitionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: RecognitionResult(lines: []))
                    return
                }

                // Sort observations top-to-bottom.
                // Vision uses a coordinate system with origin at bottom-left,
                // so we sort by (1 - boundingBox.origin.y) descending, i.e. origin.y ascending → bottom-first
                // Actually: higher origin.y = higher on screen, so sort descending
                let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

                let lines = sorted.compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedLine(
                        text: candidate.string,
                        confidence: candidate.confidence
                    )
                }

                continuation.resume(returning: RecognitionResult(lines: lines))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: finalImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: RecognitionError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// Downsample a CGImage to fit within maxDimension while keeping aspect ratio.
    private static func downsample(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let maxSide = max(width, height)
        guard maxSide > maxDimension else { return image }

        let scale = CGFloat(maxDimension) / CGFloat(maxSide)
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
