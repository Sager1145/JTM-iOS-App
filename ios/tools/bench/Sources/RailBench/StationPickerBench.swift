import Foundation
import RailCore

/// The editor's station picker, as `RideEditorView.StationPickerView` spells it.
///
/// The list is `stations` de-duplicated by code, sorted by
/// `localizedStandardCompare`, and then filtered by the query — and all three
/// steps run inside a computed property that SwiftUI re-evaluates on every
/// keystroke. Only the third depends on the query, so this measures the two
/// that do not separately from the one that does.
struct BenchStation {
    let code: String
    let name: String
    let nameRoma: String
}

func benchmarkStationPicker(root: URL) {
    let url = root.appending(path: "app/public/rail/jp-2025.json")
    guard let package = try? CompactPackage.load(contentsOf: url) else {
        print("stations: jp-2025.json unavailable")
        return
    }
    // The app hands the picker `store.stations`, which is one entry per
    // (line, station) pair — the same station on six lines is six rows before
    // the de-duplication runs.
    var stations: [BenchStation] = []
    for line in package.lines {
        for station in line.stations {
            stations.append(BenchStation(
                code: station.id, name: station.name,
                nameRoma: station.nameRoma ?? ""))
        }
    }
    let uniqueCodes = Set(stations.map(\.code)).count
    print("\nstations — \(stations.count) rows, \(uniqueCodes) distinct codes")

    func uniqueSorted() -> [BenchStation] {
        var seen = Set<String>()
        return stations.filter { seen.insert($0.code).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    measure("dedupe + localizedStandardCompare sort (per keystroke today)", repeats: 5) {
        uniqueSorted().count
    }

    let prepared = uniqueSorted()
    let prefixes = ["東", "東京", "東京駅", "shin", "shinj", "shinjuku"]
    measure("filter only, \(prefixes.count) keystrokes over the prepared list") {
        var total = 0
        for needle in prefixes {
            total += prepared.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.nameRoma.localizedCaseInsensitiveContains(needle)
                    || $0.code.localizedCaseInsensitiveContains(needle)
            }.count
        }
        return total
    }

    measure("today: dedupe + sort + filter, \(prefixes.count) keystrokes", repeats: 5) {
        var total = 0
        for needle in prefixes {
            total += uniqueSorted().filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.nameRoma.localizedCaseInsensitiveContains(needle)
                    || $0.code.localizedCaseInsensitiveContains(needle)
            }.count
        }
        return total
    }
}

/// Which spelling of the same predicate is fastest, and whether any of them
/// changes an answer. `localizedCaseInsensitiveContains` is documented as
/// `range(of:options:.caseInsensitive, range: nil, locale: .current)`, so B is
/// the same search with the locale read once instead of once per call.
func benchmarkStationPredicates(root: URL) {
    let url = root.appending(path: "app/public/rail/jp-2025.json")
    guard let package = try? CompactPackage.load(contentsOf: url) else { return }
    var names: [String] = []
    for line in package.lines {
        for station in line.stations {
            names.append(station.name)
            names.append(station.nameRoma ?? "")
            names.append(station.id)
        }
    }
    print("\npredicates — \(names.count) strings")
    let needles = ["東", "東京", "東京駅", "shin", "shinj", "shinjuku"]
    let locale = Locale.current

    measure("A localizedCaseInsensitiveContains") {
        var total = 0
        for needle in needles {
            for name in names where name.localizedCaseInsensitiveContains(needle) { total += 1 }
        }
        return total
    }
    measure("B range(of:options:.caseInsensitive, locale:) hoisted") {
        var total = 0
        for needle in needles {
            for name in names
            where name.range(of: needle, options: .caseInsensitive, range: nil, locale: locale) != nil {
                total += 1
            }
        }
        return total
    }
    measure("C NSString rangeOfString:options:range:locale:") {
        var total = 0
        for needle in needles {
            let target = needle as NSString
            for name in names {
                let haystack = name as NSString
                if haystack.range(
                    of: target as String, options: .caseInsensitive,
                    range: NSRange(location: 0, length: haystack.length),
                    locale: locale).location != NSNotFound { total += 1 }
            }
        }
        return total
    }

    // The three must agree, or none of this is a speedup.
    for needle in needles {
        let a = names.filter { $0.localizedCaseInsensitiveContains(needle) }
        let b = names.filter {
            $0.range(of: needle, options: .caseInsensitive, range: nil, locale: locale) != nil
        }
        precondition(a == b, "B disagrees with A on \(needle)")
    }
}
