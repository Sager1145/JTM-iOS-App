import Foundation

// =========================================================================
//  TransferGuideText.swift — what one piece of a row means.
//
//  Reading a row into tokens before asking what the row IS keeps every
//  question about the layout in one place. `発 8番線` is a platform wherever
//  it appears, so no rule downstream has to know that 番線 ends in the same
//  character as 上越線; `13時間24分` is a duration, so no rule has to know
//  that it is not the `5分` in 徒歩5分.
//
//  Two kinds of scanner, and the difference between them is the whole design:
//
//    * TAKE scanners (`takeCalendarDay`, `takeFare`, …) cut their match out
//      of the line wherever it sits and hand back the rest. They exist
//      because Vision does not promise where it will break a line: the route
//      summary comes back as `IC優先 47,280円 乗換2回 2338.2km` on a good run
//      and as one unspaced run of characters on a bad one, and a scanner that
//      only matched a whole word would read the second as a station name.
//
//    * WHOLE-PIECE scanners run on what is left after the takes, once it has
//      been split on spaces. They are the ones whose pattern is ambiguous —
//      `5分` is a duration on its own and part of 徒歩5分 in company — so
//      they are only allowed to speak when they are the entire piece.
// =========================================================================

extension TransferGuide {

    /// What one piece of a row means.
    enum Token: Equatable {
        case time(minutes: Int, marker: Marker?)
        case marker(Marker)
        case stationCount(Int)
        case platform(Marker, Int)
        case fare(Int)
        case duration(minutes: Int)
        case distance(km: Double)
        case transfers(Int)
        case calendar(month: Int, day: Int, year: Int?, weekday: String?)
        case cars(Int)
        case service(String, Leg.Kind)
        case destination(String)
        case note(String)
        case name(String)

        /// One OCR line, as the pieces it is made of.
        static func read(_ raw: String) -> [Token] {
            var rest = Text.normalize(raw)
            guard !rest.isEmpty else { return [] }
            var tokens: [Token] = []

            // Bounded rather than `while let`: every take shortens the line,
            // but a scanner that one day did not would hang the import on a
            // photograph rather than fail it.
            for _ in 0..<32 {
                if let (token, remainder) = Scan.takeCalendarDay(rest) {
                    tokens.append(token)
                    rest = remainder
                    continue
                }
                if let (token, remainder) = Scan.takePlatform(rest) {
                    tokens.append(token)
                    rest = remainder
                    continue
                }
                if let (count, remainder) = Scan.takeSuffixed(
                    rest, "回", after: ["乗換", "乗り換え"])
                {
                    tokens.append(.transfers(count))
                    rest = remainder
                    continue
                }
                // `乗換7回` with the 回 clipped off, which is how JR East's
                // summary line came back: the row is wide and the last glyph
                // sits at the edge of it.
                if let (count, remainder) = Scan.takePrefixed(rest, before: ["乗換", "乗り換え"]) {
                    tokens.append(.transfers(count))
                    rest = remainder
                    continue
                }
                if let (token, remainder) = Scan.takeDuration(rest) {
                    tokens.append(token)
                    rest = remainder
                    continue
                }
                if let (token, remainder) = Scan.takeDistance(rest) {
                    tokens.append(token)
                    rest = remainder
                    continue
                }
                if let (value, remainder) = Scan.takeSuffixed(rest, "円") {
                    tokens.append(.fare(value))
                    rest = remainder
                    continue
                }
                if let (value, remainder) = Scan.takeSuffixed(rest, "駅") {
                    tokens.append(.stationCount(value))
                    rest = remainder
                    continue
                }
                if let (value, remainder) = Scan.takeSuffixed(rest, "両") {
                    tokens.append(.cars(value))
                    rest = remainder
                    continue
                }
                break
            }

            let (times, remainder) = Scan.takeTimes(rest)
            tokens.append(contentsOf: times)
            for piece in Scan.split(remainder) {
                tokens.append(contentsOf: readPiece(piece))
            }
            return tokens
        }

        private static func readPiece(_ piece: String) -> [Token] {
            let text = Scan.unwrap(piece)
            guard Text.hasWordCharacter(text), !Text.isAllDecoration(text) else { return [] }

            if text == "発" { return [.marker(.departure)] }
            if text == "着" { return [.marker(.arrival)] }
            if let minutes = Scan.wholeMinutes(text) { return [.duration(minutes: minutes)] }
            if let destination = Scan.destination(text) { return [.destination(destination)] }
            if let service = Scan.service(text) { return [service] }
            if Vocabulary.isNote(text) { return [.note(text)] }

            let cleaned = Text.stripDecorations(text)
            guard Text.hasWordCharacter(cleaned) else { return [] }
            return [.name(cleaned)]
        }
    }

    // MARK: - the words the layout is made of

    enum Vocabulary {

        /// Rows below the itinerary. Everything from the first of these to the
        /// end of the screenshot is Yahoo's own furniture.
        /// Rows below the itinerary. Everything from the first of these to the
        /// end of the screenshot is Yahoo's own furniture. The wordmark is
        /// matched loosely because it is the smallest text on the page and
        /// comes back as `YAHR！`, `TZAFIOO！乗換案内` and `JAPAN`.
        static let footerMarkers = [
            "東日本アプリ", "Railway Company",
            "Yahoo", "YAHOO", "YAH", "JAPAN", "乗換案内", "CO2", "排出量", "利用時",
            "二次元コード", "ルートを共有", "運行情報", "この経路で", "経路をシェア",
        ]

        /// Service words that name a class of train rather than a line.
        static let serviceKeywords = [
            "普通", "快速", "新快速", "特快", "通勤快速", "区間快速", "急行", "快速急行",
            "特急", "準急", "区間急行", "各駅停車", "各停", "通勤", "ライナー", "エアポート",
        ]

        /// Words that decorate a leg header without changing what it is.
        static let noteKeywords = [
            "当駅始発", "直通", "乗換", "乗り換え", "隣接", "同一ホーム", "グリーン車",
            "指定席", "自由席", "立席", "優先", "運賃", "その他", "全区間", "号車",
            "前寄り", "後寄り", "始発", "終着", "定期", "現金", "座席", "予約",
            "遅延", "運休", "平常", "上り", "下り", "乗車", "降車", "ホーム", "改札",
            "有料", "女性専用", "整理券", "きっぷ", "情報なし", "確認",
            "乗換不要", "乗り換え不要", "乗換なし",
            // JR東日本アプリ's own furniture. None of it is a station, and
            // `出発時刻を変更` sits in exactly the place a boundary station
            // does — so without this the journey gains a stop called
            // "change the departure time".
            "出発時刻", "更新時刻", "移動距離", "非対応", "駅目", "降りる", "対応",
            "運行情報", "遅延情報", "設定", "経路を", "えきねっと", "サービス時間外",
            "ただいま", "予約する", "空席",
        ]

        static func isNote(_ text: String) -> Bool {
            noteKeywords.contains { text.contains($0) }
        }
    }

    // MARK: - scanners

    enum Scan {

        /// ASCII digits only. `Character.isNumber` is true for 一, 二 and 三 —
        /// their Unicode numeric type says so — which would read 三田 as a
        /// number followed by a field.
        static func isDigit(_ character: Character) -> Bool {
            character.isASCII && character.isNumber
        }

        /// The words of a line, with the split Vision invents put back.
        ///
        /// `ＪＲ特急北斗８号` comes back as `J R特急北斗8号` — one observation
        /// with a space inside it, because the two full-width capitals are far
        /// enough apart to look like separate words. A lone Latin letter
        /// followed by a word that begins with one is that split, and nothing
        /// else in this layout: `IC 優先` is not (優 is not Latin), and
        /// `Yahoo! JAPAN` is not (`Yahoo!` is not a lone letter).
        static func split(_ text: String) -> [String] {
            let words = text
                .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "|" })
                .map(String.init)
            var joined: [String] = []
            var index = 0
            while index < words.count {
                let word = words[index]
                if word.count == 1, let letter = word.first, letter.isASCII, letter.isLetter,
                    index + 1 < words.count, let next = words[index + 1].first,
                    next.isASCII, next.isLetter
                {
                    joined.append(word + words[index + 1])
                    index += 2
                    continue
                }
                joined.append(word)
                index += 1
            }
            return joined
        }

        /// Strips the brackets Yahoo wraps a duration or a note in.
        ///
        /// Balanced and whole-string only. `小倉(福岡県)` is a station whose
        /// bracket is its most useful field, and an unwrapper that took the
        /// closing paren off the end of it would leave a name that matches
        /// nothing and a prefecture that was never read.
        static func unwrap(_ text: String) -> String {
            let pairs: [(Character, Character)] = [
                ("(", ")"), ("[", "]"), ("【", "】"), ("「", "」"), ("<", ">"),
            ]
            var slice = Substring(text.trimmingCharacters(in: .whitespaces))
            while let first = slice.first, let last = slice.last, slice.count >= 2,
                pairs.contains(where: { $0.0 == first && $0.1 == last })
            {
                slice = slice.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)[...]
            }
            return String(slice)
        }

        /// `8月28日(金)`, `2026年8月28日`.
        ///
        /// A station name cannot produce this: the pattern needs ASCII digits
        /// on both sides of 月, which 三日市町 and 月見山 do not have.
        static func takeCalendarDay(_ text: String) -> (token: Token, remainder: String)? {
            let chars = Array(text)
            var index = 0
            while index < chars.count {
                guard chars[index] == "月" else {
                    index += 1
                    continue
                }
                var head = index
                var monthDigits = ""
                while head > 0, isDigit(chars[head - 1]) {
                    head -= 1
                    monthDigits.insert(chars[head], at: monthDigits.startIndex)
                }
                guard let month = Int(monthDigits), (1...12).contains(month) else {
                    index += 1
                    continue
                }
                var cursor = index + 1
                var dayDigits = ""
                while cursor < chars.count, isDigit(chars[cursor]) {
                    dayDigits.append(chars[cursor])
                    cursor += 1
                }
                guard cursor < chars.count, chars[cursor] == "日",
                    let day = Int(dayDigits), (1...31).contains(day)
                else {
                    index += 1
                    continue
                }
                cursor += 1

                var year: Int?
                if head > 0, chars[head - 1] == "年" {
                    var start = head - 1
                    var digits = ""
                    while start > 0, isDigit(chars[start - 1]) {
                        start -= 1
                        digits.insert(chars[start], at: digits.startIndex)
                    }
                    if digits.count == 4, let value = Int(digits) {
                        year = value
                        head = start
                    }
                }

                var weekday: String?
                if cursor + 2 < chars.count, chars[cursor] == "(", chars[cursor + 2] == ")" {
                    weekday = String(chars[cursor + 1])
                    cursor += 3
                }

                let remainder = String(chars[0..<head]) + String(chars[cursor...])
                return (.calendar(month: month, day: day, year: year, weekday: weekday), remainder)
            }
            return nil
        }

        /// `発 8番線`, `着2番線`, and the bare `8番線` that carries no badge.
        /// `発 8番線`, `着2番線`, and the `発 8 番線` that the real interface
        /// produces — 発 and 8 are two rounded badges and 番線 is plain text,
        /// so Vision returns three boxes and the row assembles them with
        /// spaces between. Spaces are therefore skipped on both sides of the
        /// number rather than being treated as the end of it.
        static func takePlatform(_ text: String) -> (token: Token, remainder: String)? {
            guard let range = text.range(of: "番線") else { return nil }
            let chars = Array(text)
            let suffixEnd = chars.count - text.distance(from: range.upperBound, to: text.endIndex)
            var head = suffixEnd - 2
            while head > 0, chars[head - 1] == " " { head -= 1 }
            var digits = ""
            while head > 0, isDigit(chars[head - 1]) {
                head -= 1
                digits.insert(chars[head], at: digits.startIndex)
            }
            guard let number = Int(digits) else { return nil }

            var marker = Marker.departure
            var start = head
            var probe = head - 1
            while probe >= 0, chars[probe] == " " { probe -= 1 }
            if probe >= 0, chars[probe] == "着" || chars[probe] == "発" {
                marker = chars[probe] == "着" ? .arrival : .departure
                start = probe
            }
            let remainder = String(chars[0..<start]) + String(chars[suffixEnd...])
            return (.platform(marker, number), remainder)
        }

        /// A number written immediately before `suffix`, optionally required to
        /// follow one of `after`.
        ///
        /// `47,280円` and `2駅` and `15両` are all this shape. Thousands
        /// separators are dropped rather than rejected, because Vision reads
        /// them as commas, periods and apostrophes depending on the font size.
        static func takeSuffixed(
            _ text: String, _ suffix: Character, after prefixes: [String] = []
        ) -> (value: Int, remainder: String)? {
            let chars = Array(text)
            var index = 0
            while index < chars.count {
                guard chars[index] == suffix else {
                    index += 1
                    continue
                }
                var head = index
                var digits = ""
                while head > 0, isDigit(chars[head - 1]) || Self.isSeparator(chars[head - 1]) {
                    head -= 1
                    if isDigit(chars[head]) { digits.insert(chars[head], at: digits.startIndex) }
                }
                guard !digits.isEmpty, let value = Int(digits) else {
                    index += 1
                    continue
                }
                var start = head
                if !prefixes.isEmpty {
                    let before = String(chars[0..<head])
                    guard let matched = prefixes.first(where: { before.hasSuffix($0) }) else {
                        index += 1
                        continue
                    }
                    start = head - matched.count
                }
                let remainder = String(chars[0..<start]) + String(chars[(index + 1)...])
                return (value, remainder)
            }
            return nil
        }

        /// A number written immediately AFTER one of `prefixes`.
        static func takePrefixed(
            _ text: String, before prefixes: [String]
        ) -> (value: Int, remainder: String)? {
            for prefix in prefixes {
                guard let range = text.range(of: prefix) else { continue }
                let chars = Array(text)
                var cursor = chars.count - text.distance(from: range.upperBound, to: text.endIndex)
                var digits = ""
                while cursor < chars.count, isDigit(chars[cursor]) {
                    digits.append(chars[cursor])
                    cursor += 1
                }
                guard let value = Int(digits) else { continue }
                let start = cursor - digits.count - prefix.count
                return (value, String(chars[0..<start]) + String(chars[cursor...]))
            }
            return nil
        }

        private static func isSeparator(_ character: Character) -> Bool {
            character == "," || character == "'" || character == "，"
        }

        /// `13時間24分`, `10時間`. Never a bare `5分` — that shape is decided
        /// by ``wholeMinutes(_:)`` once the line has been split, because
        /// 徒歩5分 is a walking leg and not a duration.
        static func takeDuration(_ text: String) -> (token: Token, remainder: String)? {
            let chars = Array(text)
            guard let hourIndex = chars.firstIndex(where: { $0 == "時" }),
                hourIndex + 1 < chars.count, chars[hourIndex + 1] == "間"
            else { return nil }
            var head = hourIndex
            var hourDigits = ""
            while head > 0, isDigit(chars[head - 1]) {
                head -= 1
                hourDigits.insert(chars[head], at: hourDigits.startIndex)
            }
            guard let hours = Int(hourDigits) else { return nil }

            var cursor = hourIndex + 2
            var minuteDigits = ""
            while cursor < chars.count, isDigit(chars[cursor]) {
                minuteDigits.append(chars[cursor])
                cursor += 1
            }
            var minutes = 0
            if !minuteDigits.isEmpty, cursor < chars.count, chars[cursor] == "分" {
                minutes = Int(minuteDigits) ?? 0
                cursor += 1
            }
            let remainder = String(chars[0..<head]) + String(chars[cursor...])
            return (.duration(minutes: hours * 60 + minutes), remainder)
        }

        /// `2338.2km`.
        static func takeDistance(_ text: String) -> (token: Token, remainder: String)? {
            let lowered = text.lowercased()
            guard let range = lowered.range(of: "km") else { return nil }
            let chars = Array(text)
            let suffixEnd = chars.count - lowered.distance(from: range.upperBound, to: lowered.endIndex)
            var head = suffixEnd - 2
            var digits = ""
            while head > 0, isDigit(chars[head - 1]) || chars[head - 1] == "." {
                head -= 1
                digits.insert(chars[head], at: digits.startIndex)
            }
            guard let km = Double(digits) else { return nil }
            let remainder = String(chars[0..<head]) + String(chars[suffixEnd...])
            return (.distance(km: km), remainder)
        }

        /// Every `HH:MM` in the line, with the 着/発 badge glued to it.
        ///
        /// Tolerant of the two substitutions a text recogniser makes in a
        /// column of small digits: `0` read as `O` and `1` read as `l` or
        /// `I`. That tolerance is not cosmetic. A station row is a row that
        /// has a time; `O7:26` is not one, so 桶川 would not be a station at
        /// all — the stop would vanish from the journey rather than arrive
        /// with a wrong time. The substitution is only allowed where the whole
        /// `HH:MM` shape is present, so `IC優先` cannot become a time, and a
        /// failed attempt puts back the characters it read, not the digits it
        /// hoped for.
        static func takeTimes(_ text: String) -> (tokens: [Token], remainder: String) {
            let chars = Array(text)
            var tokens: [Token] = []
            var kept: [Character] = []
            var index = 0
            while index < chars.count {
                guard index == 0 || !isDigit(chars[index - 1]),
                    let match = matchTime(chars, at: index)
                else {
                    kept.append(chars[index])
                    index += 1
                    continue
                }
                var marker = match.marker
                if marker == nil, let last = kept.last, last == "着" || last == "発" {
                    marker = last == "着" ? .arrival : .departure
                    kept.removeLast()
                }
                tokens.append(.time(minutes: match.minutes, marker: marker))
                index = match.end
            }
            return (tokens, String(kept))
        }

        /// `0`, and the letters a recogniser returns instead of one.
        private static func digitValue(_ character: Character) -> Int? {
            if isDigit(character) { return character.wholeNumberValue }
            switch character {
            case "O", "o", "Q", "ο": return 0
            case "l", "I", "|", "ｉ": return 1
            default: return nil
            }
        }

        private static func matchTime(
            _ chars: [Character], at start: Int
        ) -> (minutes: Int, marker: Marker?, end: Int)? {
            var cursor = start
            var hour = 0
            var hourDigits = 0
            while cursor < chars.count, hourDigits < 2, let value = digitValue(chars[cursor]) {
                hour = hour * 10 + value
                hourDigits += 1
                cursor += 1
            }
            guard hourDigits > 0 else { return nil }
            // A doubled separator is one separator: `O7::20` is 07:20 read
            // through a column rule that the recogniser saw as a second colon.
            var separators = 0
            while cursor < chars.count, chars[cursor] == ":" || chars[cursor] == ";" {
                separators += 1
                cursor += 1
            }
            guard separators > 0, cursor + 1 < chars.count,
                let tens = digitValue(chars[cursor]), let units = digitValue(chars[cursor + 1])
            else { return nil }
            cursor += 2
            // A third digit means this was never a time.
            if cursor < chars.count, digitValue(chars[cursor]) != nil { return nil }
            let minute = tens * 10 + units
            guard hour < 48, minute < 60 else { return nil }

            var marker: Marker?
            if cursor < chars.count, chars[cursor] == "着" || chars[cursor] == "発" {
                marker = chars[cursor] == "着" ? .arrival : .departure
                cursor += 1
            }
            return (hour * 60 + minute, marker, cursor)
        }

        /// A duration that is the whole piece: `(39分)` after unwrapping.
        static func wholeMinutes(_ text: String) -> Int? {
            guard text.hasSuffix("分") else { return nil }
            let digits = String(text.dropLast())
            guard !digits.isEmpty, digits.allSatisfy(isDigit) else { return nil }
            return Int(digits)
        }

        /// `函館行`, `熱海行き`, `博多方面行`.
        static func destination(_ text: String) -> String? {
            var body = text
            if body.hasSuffix("行き") {
                body = String(body.dropLast(2))
            } else if body.hasSuffix("行") {
                body = String(body.dropLast())
            } else {
                return nil
            }
            // 急行 and 快速急行 end in 行 and are services, not destinations.
            guard !body.isEmpty, Vocabulary.serviceKeywords.allSatisfy({ !text.contains($0) })
            else { return nil }
            if body.hasSuffix("方面") { body = String(body.dropLast(2)) }
            let cleaned = Text.stripDecorations(body)
            return Text.hasWordCharacter(cleaned) ? cleaned : nil
        }

        /// The service a leg header names, and what kind of leg it makes.
        ///
        /// Every test below runs on the part BEFORE a bracket, because a
        /// station's disambiguator can be a line: there are two 阿品 in
        /// Hiroshima and JR East tells them apart by writing 阿品（山陽本線）.
        /// Asked about the whole string, `contains("線")` reads that station as
        /// a railway and splits the journey in half at it.
        static func service(_ raw: String) -> Token? {
            let text: String = {
                guard let open = raw.firstIndex(of: "("), open != raw.startIndex,
                    raw.hasSuffix(")")
                else { return raw }
                return String(raw[raw.startIndex..<open])
            }()
            return serviceKind(text).map { .service(raw, $0) }
        }

        private static func serviceKind(_ text: String) -> Leg.Kind? {
            guard let token = classify(text) else { return nil }
            if case .service(_, let kind) = token { return kind }
            return nil
        }

        private static func classify(_ text: String) -> Token? {
            if text.contains("徒歩") { return .service(text, .walk) }
            for word in ["バス", "フェリー", "航路", "連絡船", "飛行機", "空路", "ケーブルカー"]
            where text.contains(word) {
                return .service(text, .other)
            }
            // Defensive: a platform is taken out of the line before this runs,
            // but a misread `8番線` that kept no digits must not become a line.
            if text.contains("番線") { return nil }
            if text.contains("新幹線") { return .service(text, .train) }
            if text.hasSuffix("号"), text.count >= 3 { return .service(text, .train) }
            if text.contains("ライン") { return .service(text, .train) }
            if text.contains("線") { return .service(text, .train) }
            // 鉃 and 鐵 for 鉄: the first is what Vision returned for
            // `ＩＲいしかわ鉄道` on a real capture, the second is the form the
            // character had before 1946 and still has on some signage.
            for word in ["鉄道", "鉃道", "鐵道"] where text.contains(word) {
                return .service(text, .train)
            }
            // 智頭急行 and 北越急行 are companies whose names END in 急行; the
            // train class of the same name LEADS one. The suffix is what tells
            // them apart, and reading 智頭急行 as a station put a railway
            // company in the middle of a journey.
            for suffix in ["急行", "電鉄", "軌道", "モノレール", "新交通"]
            where text.count > suffix.count && text.hasSuffix(suffix) {
                return .service(text, .train)
            }
            if Vocabulary.serviceKeywords.contains(where: { text.hasPrefix($0) }) {
                return .service(text, .train)
            }
            return nil
        }
    }

    // MARK: - text

    /// The spelling rules that stand between what Vision returns and what a
    /// rail package calls a station.
    public enum Text {

        /// Full-width ASCII to half-width, every space to a space, and the
        /// arrow to one arrow.
        ///
        /// `ＪＲ特急北斗８号` and `JR特急北斗8号` are the same service, and
        /// which one Vision returns depends on the font size it read it at.
        /// Katakana is deliberately left alone: half-width katakana is a
        /// legitimate spelling that ``matchKey(_:)`` folds later, and folding
        /// it here would change what the preview shows the reader.
        public static func normalize(_ raw: String) -> String {
            var scalars = String.UnicodeScalarView()
            for scalar in raw.unicodeScalars {
                switch scalar.value {
                case 0xFF01...0xFF5E:
                    if let half = Unicode.Scalar(scalar.value - 0xFEE0) {
                        scalars.append(half)
                    }
                case 0x3000, 0x00A0, 0x2002...0x200A, 0x202F, 0x205F:
                    scalars.append(" ")
                case 0x200B...0x200F, 0xFE00...0xFE0F, 0xFEFF, 0x2060:
                    continue
                case 0x2192, 0x21D2, 0x27A1, 0x279C, 0x2794, 0x25B6, 0x203A:
                    scalars.append("→")
                case 0x301C, 0x223C, 0x02DC:
                    scalars.append("~")
                default:
                    scalars.append(scalar)
                }
            }
            return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The 駅構内図 icon, as every shape Vision has been seen to read it.
        ///
        /// It is three horizontal bars beside a transfer station's name, and
        /// it comes back as `iii`, `III`, `≡`, `|||` or a run of colons. It is
        /// only ever stripped from the END of a name and only while a real
        /// word survives, so a station that genuinely ends in a Latin letter
        /// cannot be eaten by it.
        /// The 駅構内図 icon, as every shape Vision has been seen to return
        /// for it. `f` is on this list because it is on the real screenshots:
        /// three bars beside 東京 came back as `iff`, beside 大宮（埼玉県）as
        /// `ifi`. No Japanese station name ends in a Latin `f`, and this set
        /// is only ever stripped from the END of a name.
        static let decorations: Set<Character> = [
            "i", "I", "l", "f", "|", "!", "¦", "≡", "☰", ":", ";", "・", "･", ".", ",",
            "'", "\"", "ｉ", "ⅰ", "Ⅰ", "Ⅱ", "Ⅲ", "ⅲ", "†", "‡", "*", "＊", "-", "—", "_",
        ]

        /// Whether a character is decoration rather than a name.
        ///
        /// The set above plus the enclosed alphanumerics — ①②③, Ⓐ, ⑴ — which
        /// both apps use as badges beside a station and neither uses inside
        /// one. 小倉（福岡県）① is 小倉.
        public static func isDecoration(_ character: Character) -> Bool {
            if decorations.contains(character) { return true }
            guard let scalar = character.unicodeScalars.first,
                character.unicodeScalars.count == 1
            else { return false }
            switch scalar.value {
            case 0x2460...0x24FF, 0x3251...0x32BF, 0x1F110...0x1F16F: return true
            default: return false
            }
        }

        /// A piece that is nothing but the icon.
        ///
        /// Vision reads the three-bar 構内図 glyph as its own word about as
        /// often as it glues it to the station beside it, and `iii` survives
        /// ``stripDecorations(_:)`` — that one refuses to erase a string
        /// entirely, so it hands back the last `i`. This is the rule that says
        /// a word made only of icon is not a word.
        public static func isAllDecoration(_ text: String) -> Bool {
            !text.isEmpty && text.allSatisfy { isDecoration($0) || $0 == " " }
        }

        public static func stripDecorations(_ raw: String) -> String {
            var slice = Substring(raw.trimmingCharacters(in: .whitespaces))
            while let last = slice.last, isDecoration(last) || last == " " {
                let shortened = slice.dropLast()
                guard hasWordCharacter(String(shortened)) else { break }
                slice = shortened
            }
            while let first = slice.first, first == " " || first == "・" {
                slice = slice.dropFirst()
            }
            return String(slice)
        }

        /// `森(北海道)` → `("森", "北海道")`.
        ///
        /// Yahoo prints the bracketed prefecture only where the name is
        /// ambiguous nationally, which makes it the single most useful hint
        /// there is for choosing between two stations of one name — so it is
        /// kept rather than discarded, even though the station table spells
        /// the name without it.
        public static func stationName(_ raw: String) -> (name: String, qualifier: String?) {
            var text = stripDecorations(normalize(raw))
            // `大宮（埼玉県）ifi` — the icon glued to the closing bracket rather
            // than standing after a space. Anything past the last bracket is
            // dropped before the bracket itself is read, or the prefecture that
            // makes 大宮 unambiguous would be lost with it.
            if !text.hasSuffix(")"), let close = text.lastIndex(of: ")"),
                close != text.startIndex, text.firstIndex(of: "(") != nil
            {
                let tail = String(text[text.index(after: close)...])
                if isAllDecoration(tail) || !hasWordCharacter(stripDecorations(tail)) {
                    text = String(text[text.startIndex...close])
                }
            }
            guard text.hasSuffix(")") || text.hasSuffix("]") else { return (text, nil) }
            let close = text.last == ")" ? Character("(") : Character("[")
            guard let open = text.lastIndex(of: close), open != text.startIndex else {
                return (text, nil)
            }
            let qualifier = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            let name = stripDecorations(String(text[text.startIndex..<open]))
            guard hasWordCharacter(name), hasWordCharacter(qualifier) else { return (text, nil) }
            return (name, qualifier)
        }

        /// Whether a name could be a station at all.
        public static func looksLikeStationName(_ raw: String) -> Bool {
            let text = normalize(raw)
            // 32 rather than 24: the longest name in the five packages is
            // トヨタモビリティ富山Gスクエア五福前（五福末広町） at 25, which the
            // old ceiling rejected by one character.
            guard (1...32).contains(text.count), hasWordCharacter(text) else { return false }
            // Deliberately short. 大分, 国分 and 追分 are stations, so 分 is
            // not on this list however much it looks like a duration — the
            // duration was taken out of the line before a name was ever
            // considered, and a second guess here would only reject the
            // stations.
            //
            // 円 is not on it either, and for the same reason. It used to be,
            // and that rejected nine real stations outright: 高円寺, 新高円寺,
            // 東高円寺, 円町, 円山公園, 円座, 円田, 円行寺口 and 河野原円心.
            // A row naming one of them was claimed by nothing and the leg
            // simply ended at the stop before it. What the rule was reaching
            // for is a FARE, and a fare has digits in front of its 円 —
            // `takeSuffixed(_, "円")` has already cut those out of the line by
            // the time a name is considered, so anything still carrying
            // `<digit>円` here is a fare that scanner declined.
            for forbidden in ["番線", "時間", "→"] where text.contains(forbidden) {
                return false
            }
            if containsFareLikeYen(text) { return false }
            guard !text.allSatisfy({ Scan.isDigit($0) || $0 == ":" || $0 == "." }) else {
                return false
            }
            // At least one kanji, or two kana. Both apps write their stations
            // in Japanese, and what this rejects is what JR東日本アプリ prints
            // beside them: `KERT` and `(ERT` are its realtime badge read as
            // Latin, and `へ` is the chevron that folds a leg open. Without
            // this the journey gains stations called those.
            //
            // The two-kana floor is safe: しんざ, くびき and まつだい are the
            // shortest all-kana names in the packages, and all three are three
            // characters long.
            var kanji = 0
            var kana = 0
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x3040...0x30FF, 0xFF66...0xFF9D: kana += 1
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: kanji += 1
                default: continue
                }
            }
            return kanji >= 1 || kana >= 2
        }

        /// `1,200円` rather than 高円寺: a 円 with an ASCII digit in front of it.
        private static func containsFareLikeYen(_ text: String) -> Bool {
            var previous: Character?
            for character in text {
                if character == "円", let previous, Scan.isDigit(previous) { return true }
                previous = character
            }
            return false
        }

        /// A letter, an ideograph, a kana, a hangul syllable or a digit.
        public static func hasWordCharacter(_ text: String) -> Bool {
            text.unicodeScalars.contains { scalar in
                if CharacterSet.alphanumerics.contains(scalar) { return true }
                switch scalar.value {
                case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                    0xFF66...0xFF9D, 0xAC00...0xD7A3:
                    return true
                default:
                    return false
                }
            }
        }

        /// The letters of a key, with everything a recogniser invented
        /// dropped: `行[` read for 行田 leaves `行`, which is enough of a stem
        /// to recognise the station by when its position is already known.
        /// nil when nothing recognisable survives.
        public static func letters(_ text: String) -> String? {
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                    0xAC00...0xD7A3:
                    scalars.append(scalar)
                default:
                    if CharacterSet.alphanumerics.contains(scalar) { scalars.append(scalar) }
                }
            }
            let out = String(scalars)
            return out.isEmpty ? nil : out
        }

        /// The key a station table is looked up by.
        ///
        /// Folds the spellings that mean one station: the bracketed
        /// prefecture, a trailing 駅, half-width katakana, the small ヶ that
        /// 三ヶ日 and 三ケ日 disagree about, and the interpuncts and spaces
        /// that Vision inserts at small font sizes.
        public static func matchKey(_ raw: String) -> String {
            // NFKC first: it is the one transform that folds ﾊﾟ into パ —
            // two scalars into one — as well as ＪＲ into JR. Doing it by
            // hand would need the voiced half-width katakana table, and
            // getting that table subtly wrong is a station that never matches.
            let base = stationName(raw).name.precomposedStringWithCompatibilityMapping
            var scalars = String.UnicodeScalarView()
            for scalar in base.unicodeScalars {
                switch scalar.value {
                case 0x30F6: scalars.append(Unicode.Scalar(0x30B1) ?? scalar)  // ヶ → ケ
                case 0x30F5: scalars.append(Unicode.Scalar(0x30AB) ?? scalar)  // ヵ → カ
                // Two spellings of one kanji that Unicode keeps apart and
                // Japanese station names do not. 倶利伽羅 is written 俱利伽羅
                // on the screen and 倶利伽羅 in the package, and NFKC folds
                // neither into the other — they are separate unified
                // ideographs rather than a compatibility pair. Kept short on
                // purpose: 龍ケ崎 and 竜ヶ崎 are two DIFFERENT stations, so a
                // general old-to-new fold would merge two real places.
                case 0x4FF1: scalars.append(Unicode.Scalar(0x5036) ?? scalar)  // 俱 → 倶
                case 0x9AD9: scalars.append(Unicode.Scalar(0x9AD8) ?? scalar)  // 髙 → 高
                case 0x6FF1, 0x6FF5: scalars.append(Unicode.Scalar(0x6D5C) ?? scalar)  // 濱濵 → 浜
                case 0x7028: scalars.append(Unicode.Scalar(0x7011) ?? scalar)  // 瀨 → 瀬
                case 0x9243, 0x9435: scalars.append(Unicode.Scalar(0x9244) ?? scalar)  // 鉃鐵 → 鉄
                // The kanji/katakana homoglyphs. 二ツ井 came back as `ニツ丼`:
                // the first character is katakana ニ where the station is
                // kanji 二, and no recogniser will ever reliably tell those
                // apart because they are the same two strokes.
                //
                // Folded on BOTH sides — the query and the package go through
                // this function — so nothing is lost by choosing one of each
                // pair arbitrarily. ニセコ and 二セコ become the same key, and
                // there is only one station either could be.
                case 0x30CB: scalars.append(Unicode.Scalar(0x4E8C) ?? scalar)  // ニ → 二
                case 0x30AB: scalars.append(Unicode.Scalar(0x529B) ?? scalar)  // カ → 力
                case 0x30ED: scalars.append(Unicode.Scalar(0x53E3) ?? scalar)  // ロ → 口
                case 0x30A8: scalars.append(Unicode.Scalar(0x5DE5) ?? scalar)  // エ → 工
                case 0x30AA: scalars.append(Unicode.Scalar(0x624D) ?? scalar)  // オ → 才
                case 0x30BF: scalars.append(Unicode.Scalar(0x5915) ?? scalar)  // タ → 夕
                case 0x30C8: scalars.append(Unicode.Scalar(0x535C) ?? scalar)  // ト → 卜
                case 0x30CF: scalars.append(Unicode.Scalar(0x516B) ?? scalar)  // ハ → 八
                case 0x0020, 0x30FB, 0xFF65, 0x002D, 0x2010...0x2015:
                    continue
                default:
                    scalars.append(scalar)
                }
            }
            var text = String(scalars)
            if text.count > 1, text.hasSuffix("駅") { text = String(text.dropLast()) }
            return text.lowercased()
        }
    }
}
