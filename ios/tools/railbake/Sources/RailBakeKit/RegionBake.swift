import Foundation
import RailCore

/// "Bake level L for region R": a builder output directory in, one level's finished chains out.
///
/// The stroke work is `RailCore.NetworkStrokeBake`; this is the host-side entry that points it at
/// a directory. Later units cut the result into pieces and tiles and write the pack.
public enum RegionBake {

    /// One level of one region, from `directory`, at app zoom `zoom` (the 256-point convention
    /// `MapProjection.zoomLevel` uses; `NetworkStrokeBake.Level(appZoom:)`).
    public static func bake(
        region: String, appZoom zoom: Double, from directory: URL
    ) throws -> NetworkStrokeBake.Baked {
        let network = try DisplayInput.load(region: region, from: directory).network
        return try NetworkStrokeBake.bake(network, level: .init(appZoom: zoom, datumToken: "wgs84"))
    }

    /// Several levels of one region, reading the directory once. Levels are independent, so the
    /// result for a level equals a single-level bake of it.
    public static func bake(
        region: String, appZooms zooms: [Double], from directory: URL
    ) throws -> [NetworkStrokeBake.Baked] {
        let network = try DisplayInput.load(region: region, from: directory).network
        return try zooms.map {
            try NetworkStrokeBake.bake(network, level: .init(appZoom: $0, datumToken: "wgs84"))
        }
    }
}
