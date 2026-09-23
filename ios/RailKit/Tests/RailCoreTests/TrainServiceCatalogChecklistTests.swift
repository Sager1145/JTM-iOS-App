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

    @Test("catalog has 163 uniquely identified services")
    func catalogSize() {
        let services = TrainServiceBranding.services
        #expect(services.count == 163, "expected 163 services, found \(services.count)")
        #expect(Set(services.map(\.id)).count == services.count, "service ids must be unique")
    }

    @Test("every catalog service resolves, classifies, and has its logo",
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

        if let logoPath = service.logoPath {
            let root = try PortFixtures.repositoryRoot()
            let path = root.appending(path: "app/public").path + logoPath
            let exists = FileManager.default.fileExists(atPath: path)
            #expect(exists, "\(serviceID): logo missing at \(path)")
            if exists == false { failed.append("<logo>: missing \(logoPath)") }
        }

        Report.shared.record(serviceID: serviceID, names: service.names.count, failed: failed)
    }
}
