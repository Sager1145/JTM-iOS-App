import Foundation
import Observation

/// Snapshot admission shared by the inspector's independent evidence owners.
/// Cancelling work does not release its lease: finish after the task returns.
@MainActor @Observable public final class InspectionCaptureAdmission {
    public enum Scope { case manual, batch, analysis }
    public private(set) var scope: Scope?
    private var lease: UUID?
    public var isBusy: Bool { scope != nil }

    public init() {}

    public func begin(_ scope: Scope) -> UUID? {
        guard !isBusy else { return nil }
        let lease = UUID()
        self.lease = lease
        self.scope = scope
        return lease
    }

    public func finish(_ lease: UUID) {
        guard self.lease == lease else { return }
        self.lease = nil
        scope = nil
    }
}

/// Exact coordinate bits make invalid inputs persistable without converting
/// unknown geometry into a valid location. These are identity data, not targets.
public struct BatchInspectionCoordinateIdentity: Codable, Sendable, Equatable {
    public let longitudeBits: UInt64
    public let latitudeBits: UInt64

    public init(_ point: InspectionPoint) {
        longitudeBits = point.longitude.bitPattern
        latitudeBits = point.latitude.bitPattern
    }
}

public struct BatchInspectionIdentity: Codable, Sendable, Equatable {
    public let itemID: String
    public let fromStationID: String
    public let toStationID: String
    public let source: [BatchInspectionCoordinateIdentity]
    public let display: [BatchInspectionCoordinateIdentity]

    public init(input: InspectionInput) {
        itemID = input.id
        fromStationID = input.fromStationID
        toStationID = input.toStationID
        source = input.source.map(BatchInspectionCoordinateIdentity.init)
        display = input.display.map(BatchInspectionCoordinateIdentity.init)
    }

    public func isCurrent(for input: InspectionInput) -> Bool {
        self == Self(input: input)
    }
}

public enum BatchInspectionGeometryStatus: String, Codable, Sendable {
    case available, empty, invalid
}

public struct BatchInspectionViewpoint: Identifiable, Codable, Sendable, Equatable {
    public let itemID: String
    public let pointOrdinal: Int
    public let distanceMetres: Double
    public let coordinate: InspectionPoint

    /// Ordinals follow arclength, including coincident endpoints of closed loops.
    public var id: String { "\(itemID)#point-\(pointOrdinal)" }
}

public struct BatchInspectionItem: Codable, Sendable, Equatable {
    public let itemID: String
    public let identity: BatchInspectionIdentity
    public let geometryStatus: BatchInspectionGeometryStatus
    public let viewpoints: [BatchInspectionViewpoint]
}

/// A deterministic camera-target plan, not a railway alignment assessment.
public struct BatchInspectionPlan: Codable, Sendable, Equatable {
    public let format: String
    public let packageVersion: String
    public let spacingMetres: Double
    public let captureSettings: DiagnosticCaptureSettings?
    public let items: [BatchInspectionItem]

    public var viewpoints: [BatchInspectionViewpoint] { items.flatMap(\.viewpoints) }

    /// Directory slots belong to the original immutable inventory. Callers
    /// scoping an existing plan retain this mapping from that original plan.
    public var captureDirectoryIndices: [String: Int] {
        Dictionary(items.map(\.itemID).sorted().enumerated().map { ($0.element, $0.offset) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Reuses only the requested intervals of an existing same-contract plan.
    /// Its denser spacing and exact endpoints/ordinals survive narrowing the
    /// scope. No additional interval or changed geometry may reuse its slots.
    public func scoped(to inputs: [InspectionInput], packageVersion: String,
                       settings: DiagnosticCaptureSettings) throws -> Self {
        let safeSpacing = try settings.coverageSpacingMetres(inputs: inputs)
        guard format == "jtm-japan-batch-inspection-plan-v1", captureSettings == settings,
              spacingMetres.isFinite, spacingMetres > 0, spacingMetres <= safeSpacing,
              !inputs.isEmpty, Set(inputs.map(\.id)).count == inputs.count,
              Set(items.map(\.itemID)).count == items.count else { throw DiagnosticError.changedRequest }
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.itemID, $0) })
        let expected = Self.build(inputs: inputs, packageVersion: packageVersion,
                                  orderedItemIDs: nil, spacing: spacingMetres, settings: settings)
        guard expected.items.allSatisfy({ previous[$0.itemID] == $0 }) else { throw DiagnosticError.changedRequest }
        let selected = Set(inputs.map(\.id))
        return Self(format: format, packageVersion: packageVersion, spacingMetres: spacingMetres,
                    captureSettings: settings, items: items.filter { selected.contains($0.itemID) })
    }

    /// IDs must be unique, as in InspectionPlan. Default ordering uses that
    /// plan's risk ranking. Explicit ordering still retains every supplied item.
    /// Invalid display geometry is retained as unknown, with no target: removing
    /// invalid vertices would invent a bridge between their valid neighbors.
    public static func build(inputs: [InspectionInput], packageVersion: String,
                             orderedItemIDs: [String]? = nil) -> Self {
        build(inputs: inputs, packageVersion: packageVersion, orderedItemIDs: orderedItemIDs,
              spacing: 350, settings: nil)
    }

    public static func build(inputs: [InspectionInput], packageVersion: String,
                             orderedItemIDs: [String]? = nil, settings: DiagnosticCaptureSettings) throws -> Self {
        let spacing = try settings.coverageSpacingMetres(inputs: inputs)
        return build(inputs: inputs, packageVersion: packageVersion, orderedItemIDs: orderedItemIDs,
                     spacing: spacing, settings: settings)
    }

    private static func build(inputs: [InspectionInput], packageVersion: String,
                              orderedItemIDs: [String]?, spacing: Double,
                              settings: DiagnosticCaptureSettings?) -> Self {
        let byID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) })
        let rankedIDs = InspectionPlan.build(inputs: inputs, packageVersion: packageVersion).items.map(\.id)
        var seen: Set<String> = []
        let orderedIDs = ((orderedItemIDs ?? []) + rankedIDs).filter {
            byID[$0] != nil && seen.insert($0).inserted
        }
        let items = orderedIDs.compactMap { id -> BatchInspectionItem? in
            guard let input = byID[id] else { return nil }
            let status: BatchInspectionGeometryStatus
            if input.display.isEmpty { status = .empty }
            else if input.display.allSatisfy({ BatchGeometry.isValid($0)
                && (settings == nil || abs($0.latitude) <= 85.05112878) }) { status = .available }
            else { status = .invalid }
            let viewpoints = status == .available
                ? BatchGeometry.viewpoints(itemID: id, points: input.display, spacing: spacing) : []
            return BatchInspectionItem(itemID: id, identity: .init(input: input),
                                       geometryStatus: status, viewpoints: viewpoints)
        }
        return Self(format: "jtm-japan-batch-inspection-plan-v1", packageVersion: packageVersion,
                    spacingMetres: spacing, captureSettings: settings, items: items)
    }
}

/// Capture completion never promotes a human ReviewVerdict to aligned.
public enum BatchCaptureStatus: String, Codable, Sendable {
    case pending, captured, failed
}

public struct BatchInspectionProgress: Codable, Sendable, Equatable {
    public let viewpoint: BatchInspectionViewpoint
    public var status: BatchCaptureStatus
    public var evidencePaths: [String]
    public var note: String

    public var viewpointID: String { viewpoint.id }
    public var itemID: String { viewpoint.itemID }
}

/// Persistence belongs to the app. Identities are stored once per interval,
/// rather than duplicating a whole railway geometry for every camera target.
public struct BatchInspectionCheckpoint: Codable, Sendable, Equatable {
    public let format: String
    public let packageVersion: String
    public let identities: [BatchInspectionIdentity]
    public let captureSettings: DiagnosticCaptureSettings?
    public private(set) var progress: [BatchInspectionProgress]

    public init(plan: BatchInspectionPlan) {
        format = "jtm-japan-batch-inspection-checkpoint-v1"
        packageVersion = plan.packageVersion
        identities = plan.items.map(\.identity)
        captureSettings = plan.captureSettings
        progress = plan.viewpoints.map {
            .init(viewpoint: $0, status: .pending, evidencePaths: [], note: "")
        }
    }

    public func status(for viewpointID: String) -> BatchCaptureStatus {
        progress.first { $0.viewpointID == viewpointID }?.status ?? .pending
    }

    /// Rejects targets from a changed plan even when their stable IDs match.
    public mutating func record(viewpoint: BatchInspectionViewpoint, status: BatchCaptureStatus,
                                evidencePaths: [String] = [], note: String = "") {
        guard let index = progress.firstIndex(where: { $0.viewpoint == viewpoint }) else { return }
        progress[index].status = status
        progress[index].evidencePaths = evidencePaths
        progress[index].note = note
    }

    /// Restores app-validated capture rows in linear time. The app validates
    /// their input identities and dependencies first; this checks exact targets.
    public mutating func record(progress rows: [BatchInspectionProgress]) {
        let indices = Dictionary(progress.enumerated().map { ($0.element.viewpointID, $0.offset) },
                                 uniquingKeysWith: { first, _ in first })
        for row in rows {
            guard let index = indices[row.viewpointID],
                  progress[index].viewpoint == row.viewpoint else { continue }
            progress[index] = row
        }
    }

    /// Capture evidence follows exact inputs and endpoint identities. A package
    /// version change alone does not discard evidence. App owners must also
    /// invalidate captures when render/reference dependencies or files change.
    public func resumed(for plan: BatchInspectionPlan) -> Self {
        var result = Self(plan: plan)
        guard format == result.format, captureSettings == result.captureSettings else { return result }
        // Decode tolerates untrusted duplicate IDs without trapping.
        let oldIdentities = Dictionary(identities.map { ($0.itemID, $0) },
                                       uniquingKeysWith: { first, _ in first })
        let newIdentities = Dictionary(result.identities.map { ($0.itemID, $0) },
                                       uniquingKeysWith: { first, _ in first })
        let oldProgress = Dictionary(progress.map { ($0.viewpointID, $0) },
                                    uniquingKeysWith: { first, _ in first })
        for index in result.progress.indices {
            let current = result.progress[index]
            guard oldIdentities[current.itemID] == newIdentities[current.itemID],
                  let previous = oldProgress[current.viewpointID],
                  previous.viewpoint == current.viewpoint else { continue }
            result.progress[index] = previous
        }
        return result
    }
}

enum BatchGeometry {
    static let radius = 6_371_008.8

    static func isValid(_ point: InspectionPoint) -> Bool {
        point.longitude.isFinite && point.latitude.isFinite
            && (-180...180).contains(point.longitude) && (-90...90).contains(point.latitude)
    }

    static func distance(_ a: InspectionPoint, _ b: InspectionPoint) -> Double {
        let latA = a.latitude * .pi / 180
        let latB = b.latitude * .pi / 180
        let deltaLat = latB - latA
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let haversine = pow(sin(deltaLat / 2), 2)
            + cos(latA) * cos(latB) * pow(sin(deltaLon / 2), 2)
        return radius * 2 * asin(sqrt(min(1, max(0, haversine))))
    }

    static func interpolate(_ a: InspectionPoint, _ b: InspectionPoint,
                            fraction: Double, length: Double) -> InspectionPoint {
        if fraction <= 0 { return a }
        if fraction >= 1 { return b }
        let angle = length / radius
        let denominator = sin(angle)
        if abs(denominator) < 1e-12 {
            // Coincident/antipodal points have no unique great-circle direction.
            var delta = b.longitude - a.longitude
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            var longitude = a.longitude + delta * fraction
            if longitude > 180 { longitude -= 360 }
            if longitude < -180 { longitude += 360 }
            return .init(longitude: longitude, latitude: a.latitude + (b.latitude - a.latitude) * fraction)
        }
        let first = sin((1 - fraction) * angle) / denominator
        let second = sin(fraction * angle) / denominator
        let latA = a.latitude * .pi / 180, lonA = a.longitude * .pi / 180
        let latB = b.latitude * .pi / 180, lonB = b.longitude * .pi / 180
        let x = first * cos(latA) * cos(lonA) + second * cos(latB) * cos(lonB)
        let y = first * cos(latA) * sin(lonA) + second * cos(latB) * sin(lonB)
        let z = first * sin(latA) + second * sin(latB)
        return .init(longitude: atan2(y, x) * 180 / .pi,
                     latitude: atan2(z, hypot(x, y)) * 180 / .pi)
    }

    static func viewpoints(itemID: String, points: [InspectionPoint],
                           spacing: Double) -> [BatchInspectionViewpoint] {
        guard let first = points.first else { return [] }
        var result: [BatchInspectionViewpoint] = [
            .init(itemID: itemID, pointOrdinal: 0, distanceMetres: 0, coordinate: first)
        ]
        var travelled = 0.0
        var target = spacing
        for index in points.indices.dropFirst() {
            let a = points[index - 1], b = points[index]
            let length = distance(a, b)
            let end = travelled + length
            while length > 0 && target <= end {
                result.append(.init(itemID: itemID, pointOrdinal: result.count,
                                    distanceMetres: target,
                                    coordinate: interpolate(a, b, fraction: (target - travelled) / length,
                                                            length: length)))
                target += spacing
            }
            travelled = end
        }
        if travelled > 0, let last = points.last {
            // Numerical tolerance only merges a spacing target with the tail;
            // geographically coincident loop endpoints retain separate ordinals.
            if abs((result.last?.distanceMetres ?? 0) - travelled) < 0.000001 {
                result[result.count - 1] = .init(itemID: itemID, pointOrdinal: result.count - 1,
                                                distanceMetres: travelled, coordinate: last)
            } else {
                result.append(.init(itemID: itemID, pointOrdinal: result.count,
                                    distanceMetres: travelled, coordinate: last))
            }
        }
        return result
    }
}
