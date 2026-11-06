import CoreGraphics
import Foundation
import RailCore
import Vision

// =========================================================================
//  TextRecognizer.swift — on-device Vision text recognition, shared by the
//  transfer-guide screenshot importer and the ticket scanner.
//
//  Everything runs locally; nothing is sent over the network.
// =========================================================================

enum TextRecognizer {

    /// One recognised string and where it sat in the image.
    struct Observation: Sendable {
        var text: String
        /// Image pixels, top-left origin.
        var box: CGRect
        var confidence: Double
    }

    /// Whether this OS can read Japanese at all.
    ///
    /// Asked rather than assumed: the language list is a property of the
    /// recogniser's revision, and a device that cannot answer in Japanese
    /// would otherwise return a page of confident Latin nonsense.
    static func supportsJapanese() -> Bool { supports(languagePrefix: "ja") }

    static func supports(languagePrefix prefix: String) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        guard let languages = try? request.supportedRecognitionLanguages() else { return false }
        return languages.contains { $0.hasPrefix(prefix) }
    }

    /// Recognises `image` with the accurate recogniser.
    static func recognize(
        _ image: CGImage, languages: [String] = ["ja-JP", "en-US"]
    ) throws -> [Observation] {
        let interval = RailSignpost.jobs.begin("ocr.recognize")
        defer { RailSignpost.jobs.end("ocr.recognize", interval) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        // Off, deliberately. Language correction turns 尾久 into 御久 and
        // 籠原 into 篭原 — plausible Japanese, and a station that then matches
        // nothing. A raw misreading is at least visible as one.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()
        let results = request.results ?? []

        let width = Double(image.width)
        let height = Double(image.height)
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let top = (1 - box.maxY) * height
            let bottom = (1 - box.minY) * height
            return Observation(
                // Vision's normalised box has its origin at the BOTTOM left,
                // and everything downstream reads a document downwards.
                text: candidate.string,
                box: CGRect(x: box.minX * width, y: top, width: box.width * width, height: bottom - top),
                confidence: Double(candidate.confidence))
        }
    }

    // MARK: - tickets

    enum TicketFailure: Error {
        case unavailable
    }

    /// Recognition languages for a ticket region. Latin stays in the list for
    /// train numbers, seats and prices.
    private static func ticketLanguages(_ region: TicketRegion) -> (prefix: String, languages: [String]) {
        switch region {
        case .jp: ("ja", ["ja-JP", "en-US"])
        case .tw: ("zh", ["zh-Hant", "en-US"])
        case .kr: ("ko", ["ko-KR", "en-US"])
        }
    }

    /// Reads a ticket photo into rows, top to bottom. Fragments sitting on the
    /// same row (`東京` `→` `新大阪`) are joined left to right so the parser sees
    /// the row as printed.
    static func recognizeTicket(_ image: CGImage, region: TicketRegion) throws -> [RecognizedLine] {
        let plan = ticketLanguages(region)
        guard supports(languagePrefix: plan.prefix) else { throw TicketFailure.unavailable }
        return rows(from: try recognize(image, languages: plan.languages))
    }

    static func rows(from observations: [Observation]) -> [RecognizedLine] {
        var rows: [[Observation]] = []
        for item in observations.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last, let anchor = last.first,
                abs(item.box.midY - anchor.box.midY) < 0.6 * min(item.box.height, anchor.box.height)
            {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            return RecognizedLine(
                text: ordered.map(\.text).joined(separator: " "),
                confidence: ordered.map(\.confidence).min() ?? 0)
        }
    }
}
