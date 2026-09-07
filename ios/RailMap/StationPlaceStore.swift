import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// The Apple Maps place behind a station on this map, looked up once.
///
/// `StationPlaceLink` decides WHICH place a station is and what URL names it;
/// this is the half that cannot be unit-tested, because it is a live
/// `MKLocalSearch` against whichever map service the reader's device is served
/// by. Everything it does with the answers goes back through the rule, so the
/// only judgement made here is how many times to ask and what to remember.
///
/// ## Why it is a store rather than a call in the view
///
/// Two reasons, and both are about the same station being asked for again. A
/// reader who taps 東京 on the network, closes the card and taps the same
/// station on a ride's own dot opens two different `StationCard`s for one
/// place, and a search is a network round trip taken while a sheet is already
/// on screen. And a miss is worth remembering as firmly as a hit: on the China
/// map service every Japanese and Korean query returns
/// `MKError.placemarkNotFound`, so without a cache a reader in that service's
/// territory would pay three timeouts for every card they open, forever.
///
/// Main-actor isolated on purpose. `MKMapItem` is not `Sendable`, and the item
/// is the point — `openInMaps()` on the resolved item is what opens the real
/// place card rather than a pin, and it can only be called where the item
/// lives.
@MainActor
final class StationPlaceStore {

    static let shared = StationPlaceStore()

    /// One station, resolved.
    ///
    /// Isolated to the main actor rather than made `Sendable` by hand: it
    /// carries an `MKMapItem`, which is not `Sendable` and must not be, and an
    /// isolated type is `Sendable` precisely because its contents cannot leave.
    /// That is also what lets the in-flight `Task` hand one back.
    @MainActor
    struct Place {
        /// The map item itself, for `openInMaps()`.
        let item: MKMapItem
        /// What Apple Maps calls it. Held for the audit trail rather than for
        /// display: the card keeps its own header, which is the station's name
        /// in the reader's language, not the service's.
        let name: String
        /// The shareable link to this place, or `nil` when the service gave no
        /// identifier — every service does since iOS 18, and nothing does
        /// before it.
        let url: URL?
    }

    private struct Cached {
        let place: Place?
        let expires: ContinuousClock.Instant?
    }
    private struct Resolution {
        let place: Place?
        let definitive: Bool
    }
    private struct Lookup {
        let id: UUID
        let task: Task<Resolution, Never>
        var waiters: Set<UUID>
    }
    private var resolved: [String: Cached] = [:]
    private var running: [String: Lookup] = [:]
    /// One budget for the entire alias/fallback plan, not six seconds per query.
    private static let lookupBudget: Duration = .seconds(6)

    func place(for card: StationCard, aliases: [String] = []) async -> Place? {
        guard !Task.isCancelled else { return nil }
        // Aliases may arrive after the first card opens. A prior miss must not
        // suppress a later lookup that now has the station's local spelling.
        let key = ([card.id, card.region.code, String(card.coordinate.lon),
            String(card.coordinate.lat)] + card.searchNames + aliases).joined(separator: "\u{1f}")
        if let cached = resolved[key], cached.expires.map({ $0 > .now }) ?? true {
            return cached.place
        }
        resolved[key] = nil
        let waiter = UUID()
        let lookup: Lookup
        if var existing = running[key] {
            existing.waiters.insert(waiter)
            running[key] = existing
            lookup = existing
        } else {
            lookup = Lookup(id: UUID(), task: Task { await Self.resolve(card, aliases: aliases) },
                waiters: [waiter])
            running[key] = lookup
        }
        return await withTaskCancellationHandler {
            let answer = await lookup.task.value
            if running[key]?.id == lookup.id {
                running[key] = nil
                if !lookup.task.isCancelled, answer.definitive {
                    resolved[key] = Cached(place: answer.place,
                        expires: answer.place == nil ? .now.advanced(by: .seconds(300)) : nil)
                }
            }
            return Task.isCancelled ? nil : answer.place
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, var active = self.running[key], active.id == lookup.id else { return }
                active.waiters.remove(waiter)
                if active.waiters.isEmpty {
                    active.task.cancel()
                    self.running[key] = nil
                } else {
                    self.running[key] = active
                }
            }
        }
    }

    // MARK: - The lookup

    /// The search plan `StationPlaceLink` names, run until one step answers.
    ///
    /// The third step repeats the first query with the transport filter off.
    /// A live sweep never needed it — every station that resolved at all
    /// resolved on a filtered pass — but the filter is the service's own
    /// categorisation of a place, and a station it has failed to categorise is
    /// exactly the case a filtered search cannot see. It costs one request on
    /// stations that were going to miss anyway.
    private static func resolve(_ card: StationCard, aliases: [String]) async -> Resolution {
        let station = StationPlaceLink.Station(
            names: card.searchNames + aliases, country: card.region.code)
        let queries = StationPlaceLink.queries(for: station)
        guard let first = queries.first else { return Resolution(place: nil, definitive: true) }
        let plan = queries.map { ($0, true) } + [(first, false)]

        let deadline = ContinuousClock.now.advanced(by: lookupBudget)
        var definitive = true
        for (query, transportOnly) in plan {
            guard !Task.isCancelled, ContinuousClock.now < deadline else {
                return Resolution(place: nil, definitive: false)
            }
            let items: [MKMapItem]
            do {
                items = try await search(query, near: card.coordinate,
                    transportOnly: transportOnly, deadline: deadline)
            } catch {
                // MapKit also reports an empty result as placemarkNotFound.
                // Cache that miss; connectivity and deadline failures can retry.
                if (error as? MKError)?.code != .placemarkNotFound { definitive = false }
                continue
            }
            let candidates = items.map { item in
                StationPlaceLink.Candidate(
                    name: item.name ?? "",
                    isPublicTransport: item.pointOfInterestCategory == .publicTransport,
                    metres: metres(from: card.coordinate, to: coordinate(of: item)))
            }
            guard let index = StationPlaceLink.best(candidates, for: station) else { continue }
            let item = items[index]
            return Resolution(place: Place(item: item, name: item.name ?? "", url: placeURL(of: item)),
                definitive: true)
        }
        return Resolution(place: nil, definitive: definitive)
    }

    /// One search, inside a box around the station.
    ///
    /// Three kilometres on a side. The region is a HINT to the service rather
    /// than a filter — results outside it come back too, which is why the rule
    /// measures every candidate itself — but it is what makes 中山 mean the one
    /// under the reader's finger rather than the seven others in the country.
    private static func search(
        _ query: String, near coordinate: Coordinate, transportOnly: Bool,
        deadline: ContinuousClock.Instant
    ) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate.clLocation,
            latitudinalMeters: 3_000, longitudinalMeters: 3_000)
        // Points of interest only. An address result is a house number on the
        // street outside the station, and it is never the station.
        request.resultTypes = .pointOfInterest
        if transportOnly {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])
        }
        let operation = SearchOperation(search: MKLocalSearch(request: request))
        return try await operation.run(until: deadline)
    }

    /// Finish the waiter ourselves on timeout/cancellation: MapKit's callback
    /// may arrive later, but it can neither resume twice nor update a closed card.
    @MainActor
    private final class SearchOperation {
        @MainActor
        struct Reply {
            let items: [MKMapItem]
        }
        let search: MKLocalSearch
        var continuation: CheckedContinuation<Reply, Error>?
        var timeout: Task<Void, Never>?
        init(search: MKLocalSearch) { self.search = search }

        func run(until deadline: ContinuousClock.Instant) async throws -> [MKMapItem] {
            try Task.checkCancellation()
            let reply: Reply = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    timeout = Task { [self] in
                        do { try await Task.sleep(until: deadline, clock: .continuous) }
                        catch { return }
                        finish(.failure(URLError(.timedOut)))
                        search.cancel()
                    }
                    search.start { [weak self] response, error in
                        if let error { self?.finish(.failure(error)) }
                        else { self?.finish(.success(Reply(items: response?.mapItems ?? []))) }
                    }
                }
            } onCancel: {
                Task { @MainActor [self] in
                    finish(.failure(CancellationError()))
                    search.cancel()
                }
            }
            return reply.items
        }

        func finish(_ result: Result<Reply, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timeout?.cancel()
            timeout = nil
            continuation.resume(with: result)
        }
    }

    /// `/place?place-id=`, from the identity the service gave the place.
    ///
    /// iOS 18 is where `MKMapItem` started carrying one. Before that there is
    /// no way to name a place in a URL at all — Apple's own share sheet wrote
    /// `auid`, which was never public — so the card falls back to sending the
    /// pin, which is what it sent for every station before this existed.
    private static func placeURL(of item: MKMapItem) -> URL? {
        guard #available(iOS 18.0, *), let identifier = item.identifier else { return nil }
        return StationPlaceLink.placeURL(placeID: identifier.rawValue)
    }

    // MARK: - Geometry

    /// Where the service put the place.
    ///
    /// Both sides of the comparison are already in the basemap's own datum:
    /// `AppleMapDatum` shifted the package's coordinate into it before the
    /// station was ever drawn, and a result from MapKit is by definition in it.
    /// Measuring a GCJ-02 result against a WGS84 platform would put every
    /// Taiwanese, Hong Kong, Macanese and Korean station 500 m from itself and
    /// outside `StationPlaceLink.maxMetres`.
    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) { return item.location.coordinate }
        return legacyCoordinate(of: item)
    }

    /// `MKMapItem.placemark` is deprecated from iOS 26 and is the only way to
    /// read a position before it. Isolated here, and marked, so that supporting
    /// iOS 17 costs one warning-free function rather than a warning at the call
    /// site.
    @available(iOS, deprecated: 26.0)
    private static func legacyCoordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        item.placemark.coordinate
    }

    private static func metres(from: Coordinate, to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.lat, longitude: from.lon)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
