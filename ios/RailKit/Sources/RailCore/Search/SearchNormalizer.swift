import Foundation

/// Text → compact match keys.
///
/// Two keys per spelling:
/// - **canonical**: NFKC, lower-case, Latin diacritics stripped (Tōkyō → tokyo),
///   hiragana → katakana, Japanese shinjitai and traditional Chinese → simplified
///   (東京/东京, 線/綫/线, 鉄/鐵/铁), Hangul syllables → conjoining jamo (so a
///   half-typed syllable still prefixes), whitespace/punctuation/symbols dropped.
/// - **loose romaji**: for text that is only Latin, kana and digits: kana →
///   Hepburn, then spelling variants collapsed (shi/si, tsu/tu, chi/ti, ji/zi,
///   fu/hu, jyu/ju, m/n before b/p, long vowels ou/oo/ō → o, doubled letters).
///
/// Keys are UTF-16 code units (`[UInt16]`) so the index can store them in
/// one flat arena and compare without `String` overhead.
enum SearchNormalizer {

    // MARK: Canonical key

    /// Canonical key of `text`. When `offsets` is non-nil it receives, per key
    /// unit, the UTF-16 range of the source character that produced it.
    static func canonical(_ text: String, offsets: UnsafeMutablePointer<[Range<Int>]>? = nil) -> [UInt16] {
        var source = text
        var offsetsValid = true
        if needsCompatibilityMapping(text) {
            let mapped = text.precomposedStringWithCompatibilityMapping
            offsetsValid = mapped.utf16.count == text.utf16.count
            source = mapped
        }
        var out: [UInt16] = []
        out.reserveCapacity(source.utf16.count + 4)
        var ranges: [Range<Int>] = []
        let tracking = offsets != nil
        var position = 0
        for scalar in source.unicodeScalars {
            let width = scalar.utf16.count
            let before = out.count
            append(scalar, to: &out)
            if tracking {
                for _ in before..<out.count { ranges.append(position..<(position + width)) }
            }
            position += width
        }
        if let offsets {
            offsets.pointee = offsetsValid ? ranges : []
        }
        return out
    }

    /// Cached canonical key for repeated fields (journey list). Bounded.
    static func cachedCanonical(_ text: String) -> [UInt16] {
        cache.lock.lock()
        if let hit = cache.canonical[text] { cache.lock.unlock(); return hit }
        cache.lock.unlock()
        let key = canonical(text)
        cache.lock.lock()
        if cache.canonical.count >= 30_000 { cache.canonical.removeAll(keepingCapacity: true) }
        cache.canonical[text] = key
        cache.lock.unlock()
        return key
    }

    static func cachedLoose(_ text: String) -> [UInt16]? {
        cache.lock.lock()
        if let hit = cache.loose[text] { cache.lock.unlock(); return hit.isEmpty ? nil : hit }
        cache.lock.unlock()
        let key = loose(fromCanonical: cachedCanonical(text)) ?? []
        cache.lock.lock()
        if cache.loose.count >= 30_000 { cache.loose.removeAll(keepingCapacity: true) }
        cache.loose[text] = key
        cache.lock.unlock()
        return key.isEmpty ? nil : key
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var canonical: [String: [UInt16]] = [:]
        var loose: [String: [UInt16]] = [:]
    }
    private static let cache = Cache()

    private static func needsCompatibilityMapping(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x2150...0x24FF, 0x3200...0x33FF, 0xF900...0xFAFF, 0xFB00...0xFB4F, 0xFF61...0xFFEF:
                return true
            default: continue
            }
        }
        return false
    }

    @inline(__always)
    private static func append(_ scalar: Unicode.Scalar, to out: inout [UInt16]) {
        let v = scalar.value
        switch v {
        case 0x30...0x39, 0x61...0x7A:
            out.append(UInt16(v))
        case 0x41...0x5A:
            out.append(UInt16(v + 0x20))
        case 0xFF10...0xFF19, 0xFF41...0xFF5A:
            out.append(UInt16(v - 0xFEE0))
        case 0xFF21...0xFF3A:
            out.append(UInt16(v - 0xFEE0 + 0x20))
        case 0xC0...0x24F:
            if let folded = latinFold[Int(v - 0xC0)] { out.append(contentsOf: folded) }
        case 0x300...0x36F:
            return // combining diacritics
        case 0x3041...0x3096, 0x309D...0x309E:
            out.append(kanaFold(UInt16(v + 0x60)))
        case 0x30A1...0x30FA, 0x30FC...0x30FE:
            out.append(kanaFold(UInt16(v)))
        case 0xAC00...0xD7A3:
            let index = v - 0xAC00
            out.append(UInt16(0x1100 + index / 588))
            out.append(UInt16(0x1161 + (index % 588) / 28))
            let tail = index % 28
            if tail != 0 { appendFinal(UInt16(0x11A7 + tail), to: &out) }
        case 0x1100...0x1112, 0x1161...0x1175:
            out.append(UInt16(v))
        case 0x11A8...0x11C2:
            appendFinal(UInt16(v), to: &out)
        case 0x3131...0x318E:
            appendCompatibilityJamo(UInt16(v), to: &out)
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            out.append(hanFold(UInt16(v)))
        case 0x20000...0x3FFFF:
            for unit in scalar.utf16 { out.append(unit) }
        default:
            if ignored.contains(scalar) { return }
            if scalar.properties.isUppercase, let lower = scalar.properties.lowercaseMapping.unicodeScalars.first {
                for unit in lower.utf16 { out.append(unit) }
            } else {
                for unit in scalar.utf16 { out.append(unit) }
            }
        }
    }

    private static let ignored: CharacterSet = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters).union(.symbols).union(.controlCharacters)
        .union(CharacterSet(charactersIn: "\u{30FB}\u{FF65}"))

    /// ヶ/ヵ (and their hiragana) are read ka/ke in names: 霞ヶ関 = 霞ケ関.
    @inline(__always)
    private static func kanaFold(_ unit: UInt16) -> UInt16 {
        switch unit {
        case 0x30F6: return 0x30B1 // ヶ → ケ
        case 0x30F5: return 0x30AB // ヵ → カ
        default: return unit
        }
    }

    /// Latin-1 Supplement and Latin Extended-A/B → base letters.
    private static let latinFold: [[UInt16]?] = (0xC0...0x24F).map { value -> [UInt16]? in
        guard let scalar = Unicode.Scalar(UInt32(value)) else { return nil }
        if value == 0xD7 || value == 0xF7 { return nil } // × ÷
        let folded = String(Character(scalar))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let units = Array(folded.utf16)
        if units.allSatisfy({ (0x61...0x7A).contains($0) }) { return units }
        switch value {
        case 0xDF: return Array("ss".utf16)
        case 0xC6, 0xE6: return Array("ae".utf16)
        case 0xD8, 0xF8: return Array("o".utf16)
        case 0x152, 0x153: return Array("oe".utf16)
        case 0x141, 0x142: return Array("l".utf16)
        case 0x110, 0x111: return Array("d".utf16)
        default: return units.isEmpty ? nil : units
        }
    }

    // MARK: Hangul

    /// Final consonants are stored as the equivalent initial(s) so "서우ㄹ"
    /// and "서울" share a key prefix while typing.
    private static func appendFinal(_ unit: UInt16, to out: inout [UInt16]) {
        let table: [UInt16: [UInt16]] = finalToInitial
        if let mapped = table[unit] { out.append(contentsOf: mapped) } else { out.append(unit) }
    }

    private static let finalToInitial: [UInt16: [UInt16]] = [
        0x11A8: [0x1100], 0x11A9: [0x1101], 0x11AA: [0x1100, 0x1109], 0x11AB: [0x1102],
        0x11AC: [0x1102, 0x110C], 0x11AD: [0x1102, 0x1112], 0x11AE: [0x1103], 0x11AF: [0x1105],
        0x11B0: [0x1105, 0x1100], 0x11B1: [0x1105, 0x1106], 0x11B2: [0x1105, 0x1107],
        0x11B3: [0x1105, 0x1109], 0x11B4: [0x1105, 0x1110], 0x11B5: [0x1105, 0x1111],
        0x11B6: [0x1105, 0x1112], 0x11B7: [0x1106], 0x11B8: [0x1107], 0x11B9: [0x1107, 0x1109],
        0x11BA: [0x1109], 0x11BB: [0x110A], 0x11BC: [0x110B], 0x11BD: [0x110C], 0x11BE: [0x110E],
        0x11BF: [0x110F], 0x11C0: [0x1110], 0x11C1: [0x1111], 0x11C2: [0x1112],
    ]

    /// Compatibility jamo (what a keyboard shows mid-composition) → conjoining.
    private static func appendCompatibilityJamo(_ unit: UInt16, to out: inout [UInt16]) {
        if (0x314F...0x3163).contains(unit) { out.append(0x1161 + (unit - 0x314F)); return }
        let consonants: [UInt16: [UInt16]] = [
            0x3131: [0x1100], 0x3132: [0x1101], 0x3133: [0x1100, 0x1109], 0x3134: [0x1102],
            0x3135: [0x1102, 0x110C], 0x3136: [0x1102, 0x1112], 0x3137: [0x1103], 0x3138: [0x1104],
            0x3139: [0x1105], 0x313A: [0x1105, 0x1100], 0x313B: [0x1105, 0x1106], 0x313C: [0x1105, 0x1107],
            0x313D: [0x1105, 0x1109], 0x313E: [0x1105, 0x1110], 0x313F: [0x1105, 0x1111],
            0x3140: [0x1105, 0x1112], 0x3141: [0x1106], 0x3142: [0x1107], 0x3143: [0x1108],
            0x3144: [0x1107, 0x1109], 0x3145: [0x1109], 0x3146: [0x110A], 0x3147: [0x110B],
            0x3148: [0x110C], 0x3149: [0x110D], 0x314A: [0x110E], 0x314B: [0x110F], 0x314C: [0x1110],
            0x314D: [0x1111], 0x314E: [0x1112],
        ]
        if let mapped = consonants[unit] { out.append(contentsOf: mapped) }
    }

    // MARK: Han variants

    /// Japanese shinjitai (and a few variants ICU's Hant-Hans leaves alone) → simplified.
    private static let shinjitai: [UInt16: UInt16] = {
        let pairs: [(Character, Character)] = [
            ("鉄", "铁"), ("営", "营"), ("広", "广"), ("浜", "滨"), ("沢", "泽"), ("関", "关"),
            ("県", "县"), ("気", "气"), ("発", "发"), ("図", "图"), ("桜", "樱"), ("竜", "龙"),
            ("戸", "户"), ("楽", "乐"), ("渋", "涩"), ("円", "圆"), ("黒", "黑"), ("徳", "德"),
            ("歩", "步"), ("経", "经"), ("塩", "盐"), ("辺", "边"), ("恵", "惠"), ("駅", "驿"),
            ("蔵", "藏"), ("舘", "馆"), ("庁", "厅"), ("綫", "线"), ("栄", "荣"), ("実", "实"),
            ("売", "卖"), ("稲", "稻"), ("戦", "战"), ("険", "险"), ("検", "检"), ("権", "权"),
            ("観", "观"), ("覧", "览"), ("斉", "齐"), ("斎", "斋"), ("帰", "归"), ("亀", "龟"),
            ("滝", "泷"), ("豊", "丰"), ("芸", "艺"), ("薬", "药"), ("隠", "隐"), ("瀬", "濑"),
            ("摂", "摄"), ("弐", "贰"), ("国", "国"), ("学", "学"), ("会", "会"), ("総", "总"),
            ("続", "续"), ("単", "单"), ("巣", "巢"), ("剣", "剑"), ("壱", "壹"), ("伝", "传"),
            ("価", "价"), ("両", "两"), ("与", "与"), ("仏", "佛"), ("沼", "沼"), ("条", "条"),
            ("児", "儿"), ("鶏", "鸡"), ("姫", "姬"), ("岡", "冈"), ("郷", "乡"), ("峡", "峡"),
            ("塚", "塚"), ("鉱", "矿"), ("糸", "丝"), ("縄", "绳"), ("湾", "湾"), ("海", "海"),
            ("駒", "驹"), ("浅", "浅"), ("横", "横"), ("区", "区"), ("挙", "举"), ("拡", "扩"),
            ("灯", "灯"), ("当", "当"), ("宝", "宝"), ("尽", "尽"), ("専", "专"), ("転", "转"),
            ("軽", "轻"), ("鋼", "钢"), ("霊", "灵"), ("応", "应"), ("聴", "听"), ("読", "读"),
            ("駆", "驱"), ("騒", "骚"), ("鴎", "鸥"), ("麦", "麦"), ("黄", "黄"), ("祢", "祢"),
            ("禰", "祢"), ("髙", "高"), ("﨑", "崎"), ("嶋", "岛"), ("嶌", "岛"), ("島", "岛"),
            ("邊", "边"), ("邉", "边"), ("澤", "泽"), ("濱", "滨"), ("櫻", "樱"), ("瀧", "泷"),
            ("條", "条"), ("惠", "惠"), ("鐵", "铁"), ("鉃", "铁"), ("驛", "驿"), ("圓", "圆"),
            ("臺", "台"), ("台", "台"), ("ヶ", "ケ"),
        ]
        var table: [UInt16: UInt16] = [:]
        for (from, to) in pairs {
            guard let f = from.utf16.first, from.utf16.count == 1, let t = to.utf16.first, to.utf16.count == 1
            else { continue }
            table[f] = t
        }
        return table
    }()

    /// Lazily converted 256-character blocks of the BMP (traditional → simplified).
    private final class HanBlocks: @unchecked Sendable {
        let lock = NSLock()
        var blocks = [[UInt16]?](repeating: nil, count: 256)
    }
    private static let hanBlocks = HanBlocks()
    private static let hantToHans = StringTransform("Hant-Hans")

    /// One ideograph → its simplified form. ICU runs once per 256-character
    /// block (one transform call converts the whole block), not per character.
    @inline(__always)
    private static func hanFold(_ unit: UInt16) -> UInt16 {
        if let mapped = shinjitai[unit] { return mapped }
        let blockIndex = Int(unit >> 8)
        hanBlocks.lock.lock()
        if let block = hanBlocks.blocks[blockIndex] {
            hanBlocks.lock.unlock()
            return block[Int(unit & 0xFF)]
        }
        hanBlocks.lock.unlock()
        let block = convertBlock(UInt16(blockIndex << 8))
        hanBlocks.lock.lock()
        hanBlocks.blocks[blockIndex] = block
        hanBlocks.lock.unlock()
        return block[Int(unit & 0xFF)]
    }

    private static func convertBlock(_ base: UInt16) -> [UInt16] {
        let source = (0..<256).map { base &+ UInt16($0) }
        // Separate characters so a multi-character rule cannot shift positions.
        var joined: [UInt16] = []
        joined.reserveCapacity(512)
        for unit in source {
            joined.append((0xD800...0xDFFF).contains(unit) ? 0x20 : unit)
            joined.append(0x0A)
        }
        let converted = String(decoding: joined, as: UTF16.self).applyingTransform(hantToHans, reverse: false)
        let lines = converted?.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        var result = source
        if lines.count >= 256 {
            for index in 0..<256 {
                let units = Array(lines[index].utf16)
                if units.count == 1, !(0xD800...0xDFFF).contains(source[index]) {
                    result[index] = shinjitai[units[0]] ?? units[0]
                }
            }
        }
        return result
    }

    // MARK: Classification

    static func isLatinOrDigit(_ u: UInt16) -> Bool { (0x61...0x7A).contains(u) || (0x30...0x39).contains(u) }
    static func isKana(_ u: UInt16) -> Bool { (0x30A1...0x30FE).contains(u) }
    static func isHan(_ u: UInt16) -> Bool { (0x3400...0x9FFF).contains(u) || (0xF900...0xFAFF).contains(u) }
    static func isJamo(_ u: UInt16) -> Bool { (0x1100...0x11FF).contains(u) }

    // MARK: Loose romaji

    /// Loose romaji key of a canonical key made only of Latin letters, digits
    /// and kana. Nil when the key has other scripts (kanji, Hangul) or no letters.
    static func loose(fromCanonical key: [UInt16]) -> [UInt16]? {
        guard !key.isEmpty else { return nil }
        var ascii: [UInt8] = []
        ascii.reserveCapacity(key.count * 2)
        var hasLetter = false
        var index = 0
        while index < key.count {
            let unit = key[index]
            if isLatinOrDigit(unit) {
                if unit >= 0x61 { hasLetter = true }
                ascii.append(UInt8(unit))
                index += 1
            } else if isKana(unit) {
                hasLetter = true
                index = appendKanaRomaji(key, at: index, to: &ascii)
            } else {
                return nil
            }
        }
        guard hasLetter else { return nil }
        let collapsed = looseRules(ascii)
        return collapsed.map { UInt16($0) }
    }

    /// Hepburn for one kana (with a following small ya/yu/yo or small vowel). Returns the next index.
    private static func appendKanaRomaji(_ key: [UInt16], at index: Int, to out: inout [UInt8]) -> Int {
        let unit = key[index]
        // Sokuon and long-vowel mark: loose romaji collapses doubles and long vowels anyway.
        if unit == 0x30C3 || unit == 0x30FC { return index + 1 }
        guard let base = kanaRomaji[unit] else { return index + 1 }
        let next = index + 1 < key.count ? key[index + 1] : 0
        switch next {
        case 0x30E3, 0x30E5, 0x30E7: // small ya yu yo
            let vowel: UInt8 = next == 0x30E3 ? 0x61 : (next == 0x30E5 ? 0x75 : 0x6F)
            if base.last == 0x69 { // i-row
                let stem = base.dropLast()
                out.append(contentsOf: stem)
                if !(stem.last == 0x68 || stem == [0x6A]) { out.append(0x79) } // sh/ch/j take no y
                out.append(vowel)
                return index + 2
            }
        case 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9: // small vowels: fa ti di wi che
            let vowels: [UInt16: UInt8] = [0x30A1: 0x61, 0x30A3: 0x69, 0x30A5: 0x75, 0x30A7: 0x65, 0x30A9: 0x6F]
            if let vowel = vowels[next], base.count >= 1 {
                if unit == 0x30A6 { out.append(0x77) } else { out.append(contentsOf: base.dropLast()) }
                out.append(vowel)
                return index + 2
            }
        default: break
        }
        out.append(contentsOf: base)
        return index + 1
    }

    private static let kanaRomaji: [UInt16: [UInt8]] = {
        let rows: [(String, String)] = [
            ("ァアィイゥウェエォオ", "a a i i u u e e o o"),
            ("カガキギクグケゲコゴ", "ka ga ki gi ku gu ke ge ko go"),
            ("サザシジスズセゼソゾ", "sa za shi ji su zu se ze so zo"),
            ("タダチヂッツヅテデトド", "ta da chi ji tsu tsu zu te de to do"),
            ("ナニヌネノ", "na ni nu ne no"),
            ("ハバパヒビピフブプヘベペホボポ", "ha ba pa hi bi pi fu bu pu he be pe ho bo po"),
            ("マミムメモ", "ma mi mu me mo"),
            ("ャヤュユョヨ", "ya ya yu yu yo yo"),
            ("ラリルレロ", "ra ri ru re ro"),
            ("ヮワヰヱヲン", "wa wa i e o n"),
            ("ヴヵヶヷヸヹヺ", "vu ka ke va vi ve vo"),
        ]
        var table: [UInt16: [UInt8]] = [:]
        for (kana, romaji) in rows {
            let units = Array(kana.utf16)
            let values = romaji.split(separator: " ").map { Array($0.utf8) }
            for (unit, value) in zip(units, values) { table[unit] = value }
        }
        return table
    }()

    /// Spelling-variant collapse on lower-case ASCII.
    static func looseRules(_ input: [UInt8]) -> [UInt8] {
        var s = input
        var scratch: [UInt8] = []
        scratch.reserveCapacity(input.count * 2 + 4)
        for rule in looseRuleTable {
            replace(&s, rule.from, rule.to, scratch: &scratch)
            if rule.collapseAfter { s = collapseRuns(s) }
        }
        // "oh" before a consonant or at the end is a long o (Ohsaka, Ohmiya).
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if s[i] == 0x6F, i + 1 < s.count, s[i + 1] == 0x68 {
                let after = i + 2 < s.count ? s[i + 2] : 0
                if after == 0 || !isVowel(after) && after != 0x79 {
                    out.append(0x6F)
                    i += 2
                    continue
                }
            }
            out.append(s[i])
            i += 1
        }
        return collapseRuns(out)
    }

    private struct LooseRule {
        let from: [UInt8]
        let to: [UInt8]
        let collapseAfter: Bool
    }

    /// Applied in order. Collapsing doubled letters before `ou → o` makes
    /// "toukyou", "tookyoo" and "tōkyō" agree.
    private static let looseRuleTable: [LooseRule] = [
        ("tch", "ch"), ("sh", "sy"), ("ch", "ty"), ("ts", "t"), ("j", "zy"), ("dz", "z"),
        ("f", "h"), ("v", "b"), ("l", "r"), ("c", "k"), ("q", "k"),
        ("zyy", "zy"), ("syy", "sy"), ("tyy", "ty"), ("syi", "si"), ("tyi", "ti"), ("zyi", "zi"),
        ("di", "zi"), ("du", "zu"), ("mb", "nb"), ("mp", "np"),
    ].enumerated().map { index, pair in
        LooseRule(from: Array(pair.0.utf8), to: Array(pair.1.utf8), collapseAfter: index == 20)
    } + [LooseRule(from: Array("ou".utf8), to: Array("o".utf8), collapseAfter: false)]

    private static func replace(_ s: inout [UInt8], _ from: [UInt8], _ to: [UInt8], scratch: inout [UInt8]) {
        let n = from.count, count = s.count
        guard count >= n else { return }
        let first = from[0]
        var found = false
        for c in s where c == first { found = true; break }
        guard found else { return }
        scratch.removeAll(keepingCapacity: true)
        var i = 0
        while i < count {
            if s[i] == first, i + n <= count {
                var equal = true
                var j = 1
                while j < n { if s[i + j] != from[j] { equal = false; break }; j += 1 }
                if equal {
                    scratch.append(contentsOf: to)
                    i += n
                    continue
                }
            }
            scratch.append(s[i])
            i += 1
        }
        swap(&s, &scratch)
    }

    @inline(__always) private static func isVowel(_ c: UInt8) -> Bool {
        c == 0x61 || c == 0x65 || c == 0x69 || c == 0x6F || c == 0x75
    }

    private static func collapseRuns(_ s: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(s.count)
        for c in s where out.last != c || (c >= 0x30 && c <= 0x39) { out.append(c) }
        return out
    }
}
