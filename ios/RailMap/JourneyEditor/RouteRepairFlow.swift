import Foundation
import RailCore

/// A repair that stopped on the first span the package cannot decide alone.
struct RouteRepairGuide: Identifiable {
    let id = UUID()
    var train: Train
    var package: CompactPackage
    var fromVisitID: UUID
    var toVisitID: UUID
    var choices: [RailwayRouteChoices.Choice]
    var remaining: [RouteRepairFlow.Step]
    var repaired: Int
    var gaps: [RouteRepairFlow.GapName]
    var snapshot: Train
    var summary: String
    /// The stored ride when this guide opened. A later replace is dropped
    /// when the store no longer equals it. `train` can carry visit ids that
    /// were not written; this is the record the continuation started from.
    var storedAtOpen: Train
}


