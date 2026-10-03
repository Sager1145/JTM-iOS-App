import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// A temporary renderer input, never a persisted journey or a passport record.
nonisolated struct RailwayLinePreview: Sendable {
    let metadata: RailDisplayNetworkManifest.Line
    let stations: [RailDisplayNetworkFile.Station]
    let ride: RiddenRouteStore.DrawnRide
    let bounds: MKMapRect

    init(metadata: RailDisplayNetworkManifest.Line, file: RailDisplayNetworkFile,
         history: RailDisplayHistoryFile?, region: Region, era: DisplayNetworkEra) {
        self.metadata = metadata
        let today = RecordDate.today(in: region.clock, at: Date())
        let partRows = history?.partRows ?? [:]
        let stamps = history?.stationStampRows ?? [:]
        var seen: Set<String> = []
        stations = file.stations.filter {
            era.shows(stamps[$0.id], today: today, rideDate: nil,
                                           isStation: true)
                && seen.insert($0.stationCode).inserted
        }
        let lineStations = stations
        // Display chunks retain raw WGS84 coordinates. DrawnSegment applies
        // the device's map datum once, just as it does for a recorded journey.
        func endpoint(_ coordinate: Coordinate) -> Stop {
            let nearest = lineStations.min {
                Geometry.distanceMeters(coordinate, Coordinate(lon: $0.lon, lat: $0.lat))
                    < Geometry.distanceMeters(coordinate, Coordinate(lon: $1.lon, lat: $1.lat))
            }
            guard let nearest,
                Geometry.distanceMeters(coordinate, Coordinate(lon: nearest.lon, lat: nearest.lat)) < 150
            else { return Stop(name: "", stopType: "pass_through", rideSegment: true) }
            return Stop(name: nearest.name, n02StationCode: nearest.stationCode,
                        rideSegment: true)
        }
        var stops: [Stop] = []
        var segments: [RiddenRouteStore.DrawnSegment] = []
        var hasher = Hasher()
        for fragment in file.lines {
            let drawID = fragment.continuous == true
                ? "\(fragment.lineKey)#\(fragment.chain ?? 0)"
                : "\(fragment.lineKey)@\(fragment.lane ?? 0)"
            for (partIndex, part) in fragment.parts.enumerated() {
                let span = partRows[drawID]?[partIndex]
                guard era.shows(span, today: today, rideDate: nil) else { continue }
                let coordinates = part.compactMap(Coordinate.init(pair:))
                guard let first = coordinates.first, let last = coordinates.last,
                      coordinates.count >= 2 else { continue }
                // Disjoint branches stay disjoint: each part has its own pair
                // of stops and segment index, with no fabricated connecting rail.
                let from = endpoint(first), to = endpoint(last)
                let index = stops.count
                stops.append(contentsOf: [from, to])
                segments.append(.init(segmentIndex: index, from: from.name, to: to.name,
                                      coordinates: coordinates, country: region.code))
                for coordinate in coordinates {
                    hasher.combine(coordinate.lon)
                    hasher.combine(coordinate.lat)
                }
            }
        }
        var positions: [Int: Coordinate] = [:]
        let represented = Set(stops.compactMap(\.n02StationCode))
        for station in stations where !represented.contains(station.stationCode) {
            positions[stops.count] = AppleMapDatum.display(
                Coordinate(lon: station.lon, lat: station.lat), country: region.code)
            stops.append(Stop(name: station.name, n02StationCode: station.stationCode,
                              rideSegment: true))
            hasher.combine(station.lon)
            hasher.combine(station.lat)
        }
        ride = .init(id: "network-line|\(region.code)|\(metadata.id)", trainType: nil,
                     country: region.code, colorHex: metadata.color, visible: true,
                     segments: segments, route: .resolved, stops: stops, markerPositions: positions,
                     daySpan: Dates.daySpan(Train(id: "network-preview", number: "",
                                                origin: "", destination: "", stops: []).forDates),
                     geometryDigest: hasher.finalize())
        bounds = segments.reduce(MKMapRect.null) { $0.union($1.boundingRect) }
    }
}

struct RailwayLineCardView: View {
    let row: StationDisplay.PopupRow
    let region: Region
    let network: RailNetworkStore
    let onPreview: (RailwayLinePreview?) -> Void
    let onLocate: (MKMapRect) -> Void
    @Environment(AppLocalization.self) private var localization
    @Environment(DisplaySettings.self) private var display: DisplaySettings?
    @Environment(\.dismiss) private var dismiss
    @State private var preview: RailwayLinePreview?
    @State private var failure: String?
    @State private var reload = 0

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label).font(.title2.weight(.semibold))
                        Text(row.operatorName ?? row.company)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RouteLogoSquare(path: row.logo, color: Color(hex: row.color) ?? .accentColor,
                                    systemImage: nil, side: WorkspaceMenuMetrics.journeyLogoSide)
                }
                .accessibilityIdentifier("railwayLineHeading")
                if let preview {
                    Button {
                        onLocate(preview.bounds)
                    } label: {
                        Label(localization.journeyText("ios.journey.locateRoute"), systemImage: "viewfinder")
                    }
                    .disabled(preview.bounds.isNull)
                    .accessibilityIdentifier("railwayLineLocate")
                    LabeledContent(localization.text("ios.station.region"),
                                   value: localization.text(region.localizationKey, fallback: region.fallbackName))
                }
            }
            if let preview {
                Section {
                    ForEach(preview.stations, id: \.stationCode) { station in
                        Text(localization.stationName(station.name, code: station.stationCode, region: region))
                    }
                } header: {
                    Text(localization.editorText("ios.routeGuide.stationCount",
                         ["count": .number(Double(preview.stations.count))]))
                }
                .accessibilityIdentifier("railwayLineStations")
            } else if let failure {
                Section {
                    Text(failure).foregroundStyle(.secondary)
                    Button(localization.journeyText("ios.journey.retry")) { reload += 1 }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SheetCloseButton(accessibilityLabel: Text(localization.text("ios.close", fallback: "Close"))) {
                    dismiss()
                }
                .accessibilityIdentifier("railwayLineClose")
            }
        }
        .task(id: reload) {
            failure = nil
            do {
                let loaded = try await network.linePreview(
                    region: region, lineID: row.lineID, era: display?.networkEra ?? .current)
                try Task.checkCancellation()
                preview = loaded
                onPreview(loaded)
                onLocate(loaded.bounds)
            } catch is CancellationError {
            } catch {
                failure = error.localizedDescription
            }
        }
        .onDisappear { onPreview(nil) }
    }
}
