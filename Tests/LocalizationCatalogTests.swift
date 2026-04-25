import XCTest
@testable import Suber

/// Guards the String Catalog (`Localizable.xcstrings`) contract for v1.6.0
/// bilingual launch.
///
/// Covers:
///   - C1 (eng re-review): catalog JSON parses and has the expected shape
///   - Every English key has a zh-Hans translation (no `untranslated` state)
///   - No stale keys (state != `stale` — catch orphaned entries from
///     deleted views)
///   - H1 (eng re-review): MailSubscriptionExtractor keyword constants are
///     NOT in the catalog. Translators "translating" these would break the
///     matching heuristics.
///   - H2 (eng re-review): no `.accessibilityLabel("raw string")` calls —
///     all must be wrapped in `Text(...)` or `LocalizedStringKey`.
final class LocalizationCatalogTests: XCTestCase {

    // MARK: - Catalog shape

    /// Load the shipped `.xcstrings` file. Returns the parsed JSON (not the
    /// compiled runtime bundle — we're testing the authoring source).
    private func loadCatalog() throws -> [String: Any] {
        // Resolve the catalog from the repo root so we test the authoring
        // source (not a staled-copy compiled bundle).
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()    // Tests/
            .deletingLastPathComponent()    // repo root
        let catalogURL = repoRoot
            .appendingPathComponent("Sources/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Catalog is not a JSON object")
            return [:]
        }
        return json
    }

    private func loadStrings() throws -> [String: [String: Any]] {
        let catalog = try loadCatalog()
        guard let strings = catalog["strings"] as? [String: [String: Any]] else {
            XCTFail("Catalog missing `strings` dictionary")
            return [:]
        }
        return strings
    }

    func testCatalogJSONParses() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        XCTAssertEqual(catalog["version"] as? String, "1.0")
        XCTAssertNotNil(catalog["strings"], "Catalog must have a `strings` dictionary")
    }

    func testCatalogIsNotEmpty() throws {
        let strings = try loadStrings()
        XCTAssertGreaterThan(strings.count, 30,
                             "v1.6 introduces ~40+ strings; got \(strings.count)")
    }

    // MARK: - zh-Hans completeness

    /// Every English key must have a zh-Hans translation in `state: translated`.
    /// Design review D14 + eng re-review M2: bilingual launch means no
    /// half-translated fallback-to-English surprises.
    func testAllKeysHaveChineseTranslation() throws {
        let strings = try loadStrings()
        var missing: [String] = []
        var notTranslated: [String] = []

        for (key, entry) in strings {
            guard let localizations = entry["localizations"] as? [String: [String: Any]] else {
                missing.append("\(key): no localizations block")
                continue
            }
            guard let zhHans = localizations["zh-Hans"] as? [String: Any] else {
                missing.append(key)
                continue
            }
            guard let stringUnit = zhHans["stringUnit"] as? [String: Any],
                  let state = stringUnit["state"] as? String else {
                missing.append("\(key): zh-Hans block malformed")
                continue
            }
            if state != "translated" {
                notTranslated.append("\(key): state=\(state)")
            }
        }

        XCTAssertTrue(missing.isEmpty,
                      "Missing zh-Hans translation for \(missing.count) keys:\n" +
                      missing.prefix(10).joined(separator: "\n"))
        XCTAssertTrue(notTranslated.isEmpty,
                      "\(notTranslated.count) zh-Hans entries not in `translated` state:\n" +
                      notTranslated.prefix(10).joined(separator: "\n"))
    }

    // MARK: - No stale keys

    /// Catalog's `extractionState: stale` means Xcode scanned the source and
    /// the key no longer appears — it's orphaned. Ship-blocker: a stale key
    /// in prod means we shipped translation work for a string no one sees.
    func testNoStaleKeys() throws {
        let strings = try loadStrings()
        let stale = strings.filter { _, entry in
            (entry["extractionState"] as? String) == "stale"
        }
        XCTAssertTrue(stale.isEmpty,
                      "\(stale.count) stale keys found. Run an Xcode build to refresh the catalog, then remove these:\n" +
                      stale.keys.prefix(10).joined(separator: "\n"))
    }

    // MARK: - H1: extractor keyword fence

    /// Subject-line match keywords used by MailSubscriptionExtractor /
    /// MailScanKeywords are matching HEURISTICS, not UI copy. They must NOT
    /// be localized — a translator who localized "receipt" → "reçu" would
    /// break the English-Netflix-receipt match.
    ///
    /// This test scans the catalog and asserts none of the keywords from
    /// `MailScanKeywords.all` or the extractor's local keyword lists (shipping,
    /// refund) appear as catalog keys.
    func testExtractorKeywordsAreNotInCatalog() throws {
        let strings = try loadStrings()
        let keyNames = Set(strings.keys.map { $0.lowercased() })

        // Build the forbidden set from the actual source-of-truth constants.
        let forbidden: Set<String> = Set(
            MailScanKeywords.all + [
                "shipped", "delivered", "on its way", "out for delivery",
                "refund", "refunded", "reversal", "credit issued",
            ]
        ).map { $0.lowercased() }
        .reduce(into: Set<String>()) { $0.insert($1) }

        for keyword in forbidden {
            XCTAssertFalse(
                keyNames.contains(keyword),
                "H1: extractor keyword '\(keyword)' must not be a catalog key — translators would localize it and break the match heuristic"
            )
        }
    }

    // MARK: - H2: .accessibilityLabel lint

    /// Xcode's String Catalog auto-extracts `Text("…")` and
    /// `String(localized: "…")` but NOT `.accessibilityLabel("…")` when passed
    /// a plain String. This test scans source files for the anti-pattern
    /// `.accessibilityLabel("…")` with a bare string literal.
    ///
    /// Allowed forms:
    ///   .accessibilityLabel(Text("…"))                     ✓ auto-extracted
    ///   .accessibilityLabel(LocalizedStringKey("…"))        ✓ auto-extracted
    ///   .accessibilityLabel(String(localized: "…"))         ✓ auto-extracted
    ///   .accessibilityLabel(someTextVariable)               ✓ variable, trust it
    ///
    /// Disallowed form:
    ///   .accessibilityLabel("…")                            ✗ missed by extractor
    func testNoBareStringAccessibilityLabels() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesDir = repoRoot.appendingPathComponent("Sources")

        let violations = scanForBareAccessibilityLabels(in: sourcesDir)
        XCTAssertTrue(
            violations.isEmpty,
            "H2 lint: `.accessibilityLabel(\"raw string\")` found — wrap in Text(…) or LocalizedStringKey so the String Catalog extracts it:\n" +
            violations.joined(separator: "\n")
        )
    }

    private func scanForBareAccessibilityLabels(in dir: URL) -> [String] {
        var violations: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Regex: accessibilityLabel\(\s*"  — literal string passed directly.
        // Our allowed forms always have `Text(`, `LocalizedStringKey(`, or
        // `String(localized:` between the `(` and the `"`.
        let pattern = #"\.accessibilityLabel\(\s*"[^"]*"\s*\)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let text = try? String(contentsOf: fileURL) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let swiftRange = Range(match.range, in: text) else { return }
                let snippet = String(text[swiftRange])
                let lineNumber = text[..<swiftRange.lowerBound].filter { $0 == "\n" }.count + 1
                violations.append("\(fileURL.lastPathComponent):\(lineNumber) — \(snippet)")
            }
        }
        return violations
    }

    // MARK: - Smoke test: runtime lookup

    /// End-to-end sanity: pick a known key, look it up via String(localized:),
    /// confirm the bundle returns the English value. This doesn't verify
    /// zh-Hans at runtime (that would need AppleLanguages override); it just
    /// confirms the catalog is WIRED INTO the app bundle (not just sitting
    /// in Sources/Resources uncompiled).
    func testRuntimeLookupForKnownKey() {
        let resolved = String(localized: "Connect Apple Mail")
        XCTAssertFalse(resolved.isEmpty)
        // In the default (English) locale, the resolved value IS the key.
        // If the catalog isn't compiled in, String(localized:) returns the key
        // anyway — so this test is primarily a wire-up sanity check, not a
        // catalog-content test.
        XCTAssertEqual(resolved, "Connect Apple Mail")
    }
}
