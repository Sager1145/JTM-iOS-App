import Foundation

/// The one timetable read. Occurrences, route patterns, and line excerpts stay
/// separate results. A pattern or excerpt is never copied into `occurrences`.
public enum TimetableKnowledgeQuery {
    public enum SideStatus: Sendable, Equatable {
        case loaded
        case missing
        case damaged
        case notApplicable
    }

    public struct ClassifiedSources: Sendable {
        public let availability: ServicePatternBrowsePolicy.OccurrenceAvailability
        public let occurrences: [TrainTimetableDatabase.Trip]
        public let patterns: [TrainServicePatterns.Pattern]
        public let excerpts: [LineServiceCatalog.TimetableTrip]
        public let patternCatalog: SideStatus
        public let excerptCatalog: SideStatus

        /// A verified occurrence query that found no trips. Pattern and excerpt
        /// rows, when present, are the other catalogs — not invented occurrences.
        public var isLegalZero: Bool {
            if case .ready(let coverage) = availability {
                return coverage == .verified && occurrences.isEmpty
            }
            return false
        }
    }

    private static let excerptLoad: (trips: [LineServiceCatalog.TimetableTrip], status: SideStatus) = {
        do {
            return (try LineServiceCatalog.loadBundled().trips, .loaded)
        } catch let error as LineServiceCatalog.CatalogError {
            switch error {
            case .missingResource: return ([], .missing)
            case .invalidArtifact: return ([], .damaged)
            }
        } catch {
            return ([], .damaged)
        }
    }()

    public static func sources(
        country: String,
        serviceDate: String?,
        serviceID: String? = nil,
        database: Result<TrainTimetableDatabase, TrainTimetableDatabase.OpenFailure>,
        patterns: Result<[TrainServicePatterns.Pattern], TrainServicePatterns.CatalogFailure>? = nil,
        excerpts: [LineServiceCatalog.TimetableTrip]? = nil
    ) -> ClassifiedSources {
        let patternResult = patterns ?? TrainServicePatterns.catalogResult
        let patternStatus: SideStatus
        let patternRows: [TrainServicePatterns.Pattern]
        switch patternResult {
        case .success(let loaded):
            patternStatus = .loaded
            patternRows = filteredPatterns(loaded, country: country, serviceID: serviceID)
        case .failure(.missing):
            patternStatus = .missing
            patternRows = []
        case .failure(.damaged):
            patternStatus = .damaged
            patternRows = []
        }

        let excerptStatus: SideStatus
        let excerptRows: [LineServiceCatalog.TimetableTrip]
        if country != "jp" {
            excerptStatus = .notApplicable
            excerptRows = []
        } else if let excerpts {
            excerptStatus = .loaded
            excerptRows = filteredExcerpts(excerpts, serviceDate: serviceDate)
        } else {
            excerptStatus = excerptLoad.status
            excerptRows = filteredExcerpts(excerptLoad.trips, serviceDate: serviceDate)
        }

        guard TrainTimetableDatabase.supports(country: country) else {
            return ClassifiedSources(
                availability: .unsupported, occurrences: [], patterns: patternRows,
                excerpts: excerptRows, patternCatalog: patternStatus, excerptCatalog: excerptStatus)
        }
        switch database {
        case .failure(.unsupportedCountry):
            return classified(.unsupported, patterns: patternRows, excerpts: excerptRows,
                              patternCatalog: patternStatus, excerptCatalog: excerptStatus)
        case .failure(.missingResource):
            return classified(.missing, patterns: patternRows, excerpts: excerptRows,
                              patternCatalog: patternStatus, excerptCatalog: excerptStatus)
        case .failure(.damaged):
            return classified(.damaged, patterns: patternRows, excerpts: excerptRows,
                              patternCatalog: patternStatus, excerptCatalog: excerptStatus)
        case .success(let database):
            guard let serviceDate else {
                return classified(.notRequested, patterns: patternRows, excerpts: excerptRows,
                                  patternCatalog: patternStatus, excerptCatalog: excerptStatus)
            }
            do {
                let trips = try serviceID.map { try database.trips(for: $0, on: serviceDate) }
                    ?? database.trips(on: serviceDate)
                let coverage = try database.coverage(on: serviceDate)
                return ClassifiedSources(
                    availability: .ready(coverage.status), occurrences: trips,
                    patterns: patternRows, excerpts: excerptRows,
                    patternCatalog: patternStatus, excerptCatalog: excerptStatus)
            } catch {
                return classified(.queryFailed, patterns: patternRows, excerpts: excerptRows,
                                  patternCatalog: patternStatus, excerptCatalog: excerptStatus)
            }
        }
    }

    private static func classified(
        _ availability: ServicePatternBrowsePolicy.OccurrenceAvailability,
        patterns: [TrainServicePatterns.Pattern],
        excerpts: [LineServiceCatalog.TimetableTrip],
        patternCatalog: SideStatus,
        excerptCatalog: SideStatus
    ) -> ClassifiedSources {
        ClassifiedSources(
            availability: availability, occurrences: [], patterns: patterns, excerpts: excerpts,
            patternCatalog: patternCatalog, excerptCatalog: excerptCatalog)
    }

    private static func filteredPatterns(
        _ patterns: [TrainServicePatterns.Pattern], country: String, serviceID: String?
    ) -> [TrainServicePatterns.Pattern] {
        let servicesByID = Dictionary(
            uniqueKeysWithValues: TrainServiceBranding.services.map { ($0.id, $0) })
        return patterns.filter { pattern in
            if let serviceID, pattern.serviceId != serviceID { return false }
            if let service = servicesByID[pattern.serviceId], service.region != country { return false }
            return true
        }
    }

    private static func filteredExcerpts(
        _ trips: [LineServiceCatalog.TimetableTrip], serviceDate: String?
    ) -> [LineServiceCatalog.TimetableTrip] {
        guard let serviceDate else { return trips }
        return trips.filter { $0.serviceDates.contains(serviceDate) }
    }
}
