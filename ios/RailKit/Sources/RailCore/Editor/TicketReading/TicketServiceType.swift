import Foundation

/// The editor's train type (`local` … `highSpeed`) a ticket implies. Only
/// names whose class does not change between trains are listed; anything else
/// is left for the timetable or the reader.
public enum TicketServiceType {
    private static let japaneseHighSpeed: Set<String> = [
        "のぞみ", "ひかり", "こだま", "みずほ", "さくら", "つばめ", "はやぶさ", "はやて",
        "やまびこ", "なすの", "こまち", "つばさ", "かがやき", "はくたか", "あさま", "つるぎ",
        "とき", "たにがわ", "かもめ",
    ]

    /// `kind` is the printed document: a Japanese 特急券 means a limited
    /// express even when its name is not listed.
    public static func trainType(
        serviceName: String?, region: TicketRegion, kind: TicketKind? = nil
    ) -> String? {
        let name = (serviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch region {
        case .jp:
            if japaneseHighSpeed.contains(name) { return "highSpeed" }
            return kind == .expressSupplement ? "limitedExpress" : nil
        case .tw:
            if name.contains("高鐵") || name.uppercased().hasPrefix("THSR") { return "highSpeed" }
            if ["自強", "普悠瑪", "太魯閣"].contains(where: name.contains) { return "limitedExpress" }
            if name.contains("莒光") { return "express" }
            if name.contains("區間快") { return "rapid" }
            if name.contains("區間") || name.contains("復興") { return "local" }
            return nil
        case .kr:
            let upper = name.uppercased()
            if upper.hasPrefix("KTX") || upper.hasPrefix("SRT") { return "highSpeed" }
            if upper.hasPrefix("ITX") || name.contains("새마을") { return "limitedExpress" }
            if name.contains("무궁화") || name.contains("누리로") { return "express" }
            return nil
        }
    }

    /// The record's number as the region writes it: のぞみ23号, 自強 123次, KTX 101.
    public static func displayNumber(serviceName: String?, serviceNumber: String?, region: TicketRegion) -> String? {
        let name = (serviceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let number = TimetableTicketMatch.normalizedNumber(serviceNumber)
        switch (name.isEmpty, number) {
        case (true, nil): return nil
        case (false, nil): return name
        case (_, let number?):
            switch region {
            case .jp: return name + number + "号"
            case .tw: return name.isEmpty ? number + "次" : name + " " + number + "次"
            case .kr: return name.isEmpty ? number : name + " " + number
            }
        }
    }
}
