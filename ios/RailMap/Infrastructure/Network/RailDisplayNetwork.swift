import CryptoKit
import Foundation
import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// Reads and validates the bundled display-network files for the native renderer.
enum RailDisplayNetwork {
    static let subdirectory = "rail-display-network"

    static func manifest(bundle: Bundle = .main) throws -> RailDisplayNetworkManifest {
        guard let url = bundle.url(
            forResource: "manifest", withExtension: "json", subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingManifest }
        return try JSONDecoder().decode(
            RailDisplayNetworkManifest.self, from: Data(contentsOf: url)).validated()
    }

    /// Reads a region's blob whole via `mmap` (`Data(contentsOf:options:.alwaysMapped)`);
    /// callers slice one railway's chunk out of it with `chunk(_:blob:catalog:families:)`.
    /// The blob is never itself re-hashed — see that function's doc comment
    /// for why the whole-file SHA has been dropped at runtime.
    static func blob(
        _ record: RailDisplayNetworkManifest.RegionRecord, bundle: Bundle = .main
    ) throws -> Data {
        guard let url = bundle.url(
            forResource: record.file, withExtension: nil, subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingRegion(record.region) }
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count == record.bytes else {
            throw RailDisplayNetworkError.corruptRegion(record.region)
        }
        return data
    }

    /// Slices one railway's chunk out of its region's `blob`, then decodes
    /// and validates it.
    ///
    /// Runtime integrity now stops at the chunk: the whole-blob SHA-256 that
    /// v1 checked on every region load is dropped here, because the blob is
    /// `mmap`ped rather than copied and hashing it would mean paging in
    /// megabytes just to load one railway. The per-chunk SHA-256 is instead
    /// verified only in `#if DEBUG` builds, as a guard against a stale or
    /// hand-edited bundle during development; a release build trusts the
    /// bundle's own code signature.
    static func chunk(
        _ entry: RailDisplayNetworkIndex.Entry, blob: Data,
        detail: DisplayDetail = .full,
        catalog: [String: RailDisplayNetworkManifest.Line],
        families: [String: RailDisplayNetworkFile.FamilyColor]
    ) throws -> RailDisplayNetworkFile {
        // The overview chunk when one was requested AND the manifest has
        // one; otherwise (including a whole-region or overview-less line)
        // the full chunk, exactly as before this field existed. The
        // detail validated below is the one actually sliced, not the one
        // asked for, so a request for an absent overview quietly loads
        // full rather than failing its own detail check.
        let usesOverview = detail == .overview && entry.overview != nil
        let sliced = usesOverview ? entry.overview! : entry.chunk
        let effectiveDetail: DisplayDetail = usesOverview ? .overview : .full
        let data: Data
        do {
            data = try DisplayChunkReader.slice(
                blob, offset: sliced.offset, length: sliced.length)
        } catch {
            throw RailDisplayNetworkError.chunkOutOfRange(entry.id)
        }
        #if DEBUG
        guard SHA256.hash(data: data).hex == sliced.sha256 else {
            throw RailDisplayNetworkError.corruptChunk(entry.id)
        }
        #endif
        return try JSONDecoder().decode(RailDisplayNetworkFile.self, from: data)
            .validated(
                region: entry.region, lineId: entry.id, catalog: catalog, families: families,
                detail: effectiveDetail)
    }

    /// The history side file, when the manifest names one and the bundle has
    /// it. A missing file is not a failed region — the current network still
    /// draws. A named file whose bytes or digest disagree is.
    static func history(
        _ record: RailDisplayNetworkManifest.RegionRecord, bundle: Bundle = .main
    ) throws -> RailDisplayHistoryFile? {
        guard let name = record.historyFile else { return nil }
        guard let url = bundle.url(
            forResource: name, withExtension: nil, subdirectory: subdirectory)
        else { return nil }
        let data = try Data(contentsOf: url)
        if let historyBytes = record.historyBytes, data.count != historyBytes {
            throw RailDisplayNetworkError.corruptRegion(record.region)
        }
        if let digest = record.historySHA256,
           SHA256.hash(data: data).hex != digest {
            throw RailDisplayNetworkError.corruptRegion(record.region)
        }
        let file = try JSONDecoder().decode(RailDisplayHistoryFile.self, from: data)
        guard file.format == RailDisplayHistoryFile.format, file.region == record.region else {
            throw RailDisplayNetworkError.unsupportedFormat(file.format)
        }
        return file
    }

    /// Reads station identities separately from viewport geometry, so selected
    /// journeys can rank hubs even with the network hidden or evicted.
    static func stationIdentity(
        region record: RailDisplayNetworkManifest.RegionRecord, bundle: Bundle = .main
    ) throws -> RailDisplayStationTable {
        guard let stationsFile = record.stationsFile,
              let url = bundle.url(
                  forResource: stationsFile, withExtension: nil, subdirectory: subdirectory)
        else { throw RailDisplayNetworkError.missingRegion(record.region) }
        let data = try Data(contentsOf: url)
        let table = try JSONDecoder().decode(RailDisplayStationTable.self, from: data)
        guard table.format == RailDisplayStationTable.format else {
            throw RailDisplayNetworkError.unsupportedFormat(table.format)
        }
        return table
    }

    /// Region records the padded map rect touches, at this camera's zoom.
    /// Uses the index's precomputed floors and world-shifted extents.
    static func records(
        intersecting rect: MKMapRect,
        cameraZoom: Double,
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkManifest.RegionRecord] {
        let world = MKMapRect.world.size.width
        return index.orderedRegions.compactMap { region in
            guard let record = index.recordsByRegion[region],
                  let floor = index.regionFloors[region],
                  RailStyle.zoom(fromMapLibre: Double(floor)) <= cameraZoom else { return nil }
            let extent = record.mapRect
            guard !extent.isNull else { return nil }
            guard [-world, 0, world].contains(where: { shift in
                extent.offsetBy(dx: shift, dy: 0).intersects(rect)
            }) else { return nil }
            return record
        }
    }

    /// How far past a line's own minimum camera zoom the loader still
    /// prefetches it — in this app's zoom units, same ruler as
    /// `minimumCameraZoom`.
    static let zoomPrefetchMargin = 1.0

    /// Railway lines the padded map rect touches, this camera is close
    /// enough in to draw, or that one of those lines names in `dependsOn`
    /// (a continuous-stroke line drawn partly from another line's alignment
    /// — see `RailCore.ContinuousStroke.Follow`). A dependency is pulled in
    /// regardless of its own rect or zoom eligibility, because the line that
    /// depends on it needs its geometry to draw at all.
    ///
    /// Output is grouped by `index.orderedRegions`, each region's lines in
    /// blob order (D2) — the same order `publishDisplayNetwork` draws in.
    static func lines(
        intersecting rect: MKMapRect,
        cameraZoom: Double,
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkIndex.Entry] {
        let world = MKMapRect.world.size.width
        let regions = records(intersecting: rect, cameraZoom: cameraZoom, in: index)

        var base: [RailDisplayNetworkIndex.Entry] = []
        for record in regions {
            for entry in index.entriesByRegion[record.region] ?? [] {
                guard entry.minimumCameraZoom <= cameraZoom + zoomPrefetchMargin,
                      !entry.mapRect.isNull,
                      [-world, 0, world].contains(where: { shift in
                          entry.mapRect.offsetBy(dx: shift, dy: 0).intersects(rect)
                      })
                else { continue }
                base.append(entry)
            }
        }

        return closure(of: base, in: index)
    }

    /// The transitive closure of `entries` over `dependsOn`: every entry
    /// named, directly or indirectly, by one already in the list, added
    /// regardless of its own rect or zoom eligibility — a line that depends
    /// on another needs that line's geometry to draw at all. Output is
    /// grouped by `index.orderedRegions`, each region's lines in blob order
    /// (D2), same as ``lines(intersecting:cameraZoom:in:)``.
    static func closure(
        of entries: [RailDisplayNetworkIndex.Entry],
        in index: RailDisplayNetworkIndex
    ) -> [RailDisplayNetworkIndex.Entry] {
        let allEntries = index.entryByID
        var selected = Set(entries.map(\.id))
        var frontier = Array(selected)
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                guard let entry = allEntries[id] else { continue }
                for dependencyID in entry.dependsOn where !selected.contains(dependencyID) {
                    guard allEntries[dependencyID] != nil else { continue }
                    selected.insert(dependencyID)
                    next.append(dependencyID)
                }
            }
            frontier = next
        }
        return index.orderedRegions.flatMap { region in
            (index.entriesByRegion[region] ?? []).filter { selected.contains($0.id) }
        }
    }

    static func popup(
        for station: RailDisplayNetworkFile.Station,
        catalog: [String: RailDisplayNetworkManifest.Line]
    ) -> StationDisplay.PopupModel {
        var seen: Set<String> = []
        var rows: [StationDisplay.PopupRow] = []
        for key in station.groupLineKeys {
            guard let line = catalog[key] else { continue }
            let displayKey = StationDisplay.popupIdentityKey(
                region: line.region, operatorName: line.operator,
                name: line.name, renderGroup: line.renderGroup)
            guard seen.insert(displayKey).inserted else { continue }
            let branding = OperatorBranding.Line(
                lineId: line.id, operator: line.operator, logo: line.logo ?? line.operatorLogo)
            let logo = OperatorBranding.logoForLine(branding)
            let label = line.nameRoma.flatMap { $0.isEmpty ? nil : "\(line.name) (\($0))" }
                ?? line.name
            rows.append(.init(
                lineID: line.id,
                company: OperatorBranding.companyFor(
                    operator: line.operator, lineName: line.name),
                label: label, color: line.color, logo: logo,
                logoNeedsDarkMatte: OperatorBranding.logoNeedsDarkMatte(logo),
                operatorName: line.operator))
        }
        rows.sort {
            $0.label.compare($1.label, options: [], locale: Locale(identifier: "en_US"))
                == .orderedAscending
        }
        return .init(
            name: station.name, nameRoma: station.nameRoma ?? "", readings: nil, lines: rows)
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
