import Foundation
import RailCore
import Testing

/// Per-service checklist over the whole bundled service catalog (every entry
/// is its own test case): each name resolves back to its own service (with
/// and without a train number), the resolved train classifies as a limited
/// express, and the logo asset exists. The aggregate report is written only
/// when `TRAIN_CATALOG_CHECK_REPORT` is set to an output file path.
struct TrainServiceCatalogChecklistTests {
    /// Aggregates per-service results across parallel test cases and rewrites
    /// the JSON report after each update.
    private final class Report: @unchecked Sendable {
        static let shared = Report()
        private let lock = NSLock()
        private var entries: [String: [String: Any]] = [:]

        func record(serviceID: String, names: Int, failed: [String]) {
            lock.lock()
            defer { lock.unlock() }
            entries[serviceID] = ["names": names, "failed": failed]
            guard let path = ProcessInfo.processInfo.environment["TRAIN_CATALOG_CHECK_REPORT"]
            else { return }
            if let data = try? JSONSerialization.data(
                withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
            {
                try? data.write(to: URL(filePath: path))
            }
        }
    }

    private static func train(number: String, region: String) -> Train {
        Train(
            id: "test", number: number, numberEn: nil, trainType: nil,
            company: nil, origin: "A", destination: "B",
            routePolicy: nil, routeSections: nil,
            stops: [Stop(name: "A"), Stop(name: "B")], region: region)
    }

    private static func numberedCaption(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.isASCII ? "\(name) 1" : "\(name)1号"
    }

    private static func normalizedVersionDate(_ value: String, endOfPeriod: Bool) -> String? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts[0].count == 4,
              parts[0].allSatisfy(\.isNumber), let year = Int(parts[0]),
              (1...9999).contains(year)
        else { return nil }

        var month = endOfPeriod ? 12 : 1
        if parts.count >= 2 {
            guard parts[1].count == 2, parts[1].allSatisfy(\.isNumber),
                  let parsedMonth = Int(parts[1]), (1...12).contains(parsedMonth)
            else { return nil }
            month = parsedMonth
        }

        let maximumDay: Int
        switch month {
        case 2:
            let leapYear = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            maximumDay = leapYear ? 29 : 28
        case 4, 6, 9, 11:
            maximumDay = 30
        default:
            maximumDay = 31
        }

        var day = endOfPeriod ? maximumDay : 1
        if parts.count == 3 {
            guard parts[2].count == 2, parts[2].allSatisfy(\.isNumber),
                  let parsedDay = Int(parts[2]), (1...maximumDay).contains(parsedDay)
            else { return nil }
            day = parsedDay
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    @Test("catalog has 241 uniquely identified services")
    func catalogSize() {
        let services = TrainServiceBranding.services
        #expect(services.count == 241, "expected 241 services, found \(services.count)")
        #expect(Set(services.map(\.id)).count == services.count, "service ids must be unique")
    }

    @Test("every catalog service resolves, classifies, and validates any configured logo",
          arguments: TrainServiceBranding.services.map(\.id))
    func serviceChecklist(serviceID: String) throws {
        let service = try #require(
            TrainServiceBranding.services.first { $0.id == serviceID },
            "service \(serviceID) missing from catalog")
        let region = service.region.isEmpty ? "jp" : service.region
        var failed: [String] = []

        #expect(service.names.isEmpty == false, "\(serviceID): has no names")
        if service.names.isEmpty { failed.append("<none>: names empty") }

        for name in service.names {
            let numbered = Self.train(number: Self.numberedCaption(name), region: region)
            let numberedID = TrainServiceBranding.service(for: numbered)?.id
            #expect(numberedID == serviceID,
                    "\(serviceID): numbered caption '\(numbered.number)' resolved to \(numberedID ?? "nil")")
            if numberedID != serviceID {
                failed.append("\(name): numbered resolves to \(numberedID ?? "nil")")
            }

            let limited = TrainServiceBranding.isLimitedExpress(numbered)
            #expect(limited, "\(serviceID): '\(numbered.number)' is not classified as limited express")
            if limited == false { failed.append("\(name): isLimitedExpress false") }

            let plain = Self.train(number: name, region: region)
            let plainID = TrainServiceBranding.service(for: plain)?.id
            #expect(plainID == serviceID,
                    "\(serviceID): plain name '\(name)' resolved to \(plainID ?? "nil")")
            if plainID != serviceID {
                failed.append("\(name): plain resolves to \(plainID ?? "nil")")
            }
        }

        let root = try PortFixtures.repositoryRoot()
        if let logoPath = service.logoPath {
            let path = root.appending(path: "app/public").path + logoPath
            let exists = FileManager.default.fileExists(atPath: path)
            #expect(exists, "\(serviceID): logo missing at \(path)")
            if exists == false { failed.append("<logo>: missing \(logoPath)") }
        }

        let versions = service.logos ?? []
        var ranges: [(index: Int, start: String, end: String)] = []
        for (index, version) in versions.enumerated() {
            let path = root.appending(path: "app/public").path + version.path
            let exists = FileManager.default.fileExists(atPath: path)
            #expect(exists, "\(serviceID): versioned logo missing at \(path)")
            if exists == false { failed.append("<logo[\(index)]>: missing \(version.path)") }

            let start = version.validFrom.flatMap {
                Self.normalizedVersionDate($0, endOfPeriod: false)
            }
            let end = version.validUntil.flatMap {
                Self.normalizedVersionDate($0, endOfPeriod: true)
            }
            let validStart = version.validFrom == nil || start != nil
            let validEnd = version.validUntil == nil || end != nil
            #expect(validStart, "\(serviceID): logo version \(index) has invalid validFrom")
            #expect(validEnd, "\(serviceID): logo version \(index) has invalid validUntil")
            if validStart == false { failed.append("<logo[\(index)]>: invalid validFrom") }
            if validEnd == false { failed.append("<logo[\(index)]>: invalid validUntil") }

            guard validStart, validEnd else { continue }
            let normalizedStart = start ?? "0001-01-01"
            let normalizedEnd = end ?? "9999-12-31"
            let ordered = normalizedStart <= normalizedEnd
            #expect(ordered, "\(serviceID): logo version \(index) starts after it ends")
            if ordered == false {
                failed.append("<logo[\(index)]>: validFrom is after validUntil")
            } else {
                ranges.append((index, normalizedStart, normalizedEnd))
            }
        }

        for left in ranges.indices {
            for right in ranges.indices where right > left {
                let overlaps = ranges[left].start <= ranges[right].end
                    && ranges[right].start <= ranges[left].end
                #expect(overlaps == false,
                        "\(serviceID): logo versions \(ranges[left].index) and \(ranges[right].index) overlap")
                if overlaps {
                    failed.append("<logos>: versions \(ranges[left].index) and \(ranges[right].index) overlap")
                }
            }
        }

        // A nil default is allowed: dates outside every version (an era with
        // no mark of its own) fall back to the operator logo.
        if versions.isEmpty == false {
            let containsDefault = service.logoPath.map {
                defaultPath in versions.contains { $0.path == defaultPath }
            } ?? true
            #expect(containsDefault, "\(serviceID): default logo is not one of its versions")
            if containsDefault == false { failed.append("<logos>: default path not versioned") }
        }

        Report.shared.record(serviceID: serviceID, names: service.names.count, failed: failed)
    }
}
