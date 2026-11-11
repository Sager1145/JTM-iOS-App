import Foundation

/// Reads kanji text aloud as Latin letters, so a wrong same-reading kanji from
/// an IME (渋矢 for 渋谷) can still find the station.
///
/// The bundled readings table covers only a small share of stations and no
/// single characters, so a reading of arbitrary query text cannot be derived
/// from it; the system's Japanese transcription is used instead. Tests stub it.
public protocol SearchReadingProvider: Sendable {
    /// A Latin transcription of `text` (any case, macrons allowed), or nil.
    func latinReading(of text: String) -> String?
}

/// The system transcription (`CFStringTokenizer`, Japanese).
public struct SystemSearchReading: SearchReadingProvider {
    public init() {}

    public func latinReading(of text: String) -> String? {
        #if canImport(CoreFoundation) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
        let source = text as CFString
        let range = CFRangeMake(0, CFStringGetLength(source))
        let locale = CFLocaleCreate(nil, "ja" as CFString)
        let tokenizer = CFStringTokenizerCreate(nil, source, range, CFOptionFlags(kCFStringTokenizerUnitWordBoundary), locale)
        var result = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String else { return nil }
            result += latin
        }
        return result.isEmpty ? nil : result
        #else
        return nil
        #endif
    }
}

/// A fixed table, for tests.
public struct StubSearchReading: SearchReadingProvider {
    public var readings: [String: String]
    public init(_ readings: [String: String]) { self.readings = readings }
    public func latinReading(of text: String) -> String? { readings[text] }
}
