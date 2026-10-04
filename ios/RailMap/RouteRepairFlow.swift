import Foundation
import RailCore

/// Walks failing spans in travel order. A unique plan that does not delete
/// authored stops is applied. The first span that needs a choice pauses the
/// rest. Visit ids keep later spans stable after earlier inserts.
enum RouteRepairFlow {
    struct Step: Equatable, Sendable {
        var fromVisitID: UUID
        var toVisitID: UUID
        var reason: RouteRepair.Reason
    }

    struct GapName: Equatable, Sendable {
        var from: String
        var to: String
    }

    struct Pause: Equatable {
        var fromVisitID: UUID
        var toVisitID: UUID
        var choices: [RailwayRouteChoices.Choice]
        var remaining: [Step]
    }

    struct Advance: Equatable {
        var train: Train
        var repaired: Int
        var gaps: [GapName]
        var pause: Pause?
    }

    static func steps(_ spans: [RouteRepair.Span], in train: Train) -> (train: Train, steps: [Step]) {
        let prepared = RailwayRouteEditing.preparing(train)
        var steps: [Step] = []
        for span in spans {
            guard prepared.stops.indices.contains(span.fromVisitIndex),
                  prepared.stops.indices.contains(span.toVisitIndex),
                  let from = prepared.stops[span.fromVisitIndex].routeEditing?.visitID,
                  let to = prepared.stops[span.toVisitIndex].routeEditing?.visitID,
                  from != to else { continue }
            steps.append(Step(fromVisitID: from, toVisitID: to, reason: span.reason))
        }
        return (prepared, steps)
    }

    static func advance(
        train: Train, package: CompactPackage, aliases: [String: String], steps: [Step]
    ) -> Advance {
        var train = RailwayRouteEditing.preparing(train)
        var repaired = 0
        var gaps: [GapName] = []
        var index = steps.startIndex
        while index < steps.endIndex {
            let step = steps[index]
            guard let fromIndex = train.stops.firstIndex(where: { $0.routeEditing?.visitID == step.fromVisitID }),
                  let toIndex = train.stops.firstIndex(where: { $0.routeEditing?.visitID == step.toVisitID }),
                  fromIndex < toIndex else {
                gaps.append(GapName(from: name(step.fromVisitID, in: train), to: name(step.toVisitID, in: train)))
                index += 1
                continue
            }
            let span = RouteRepair.Span(
                fromVisitIndex: fromIndex, toVisitIndex: toIndex, reason: step.reason)
            switch RouteRepair.attempt(span: span, train: train, package: package, stationAliases: aliases) {
            case .unique(let choice):
                guard let plan = RailwayRouteEditing.plan(
                    train: train, choice: choice, fromVisitID: step.fromVisitID, toVisitID: step.toVisitID
                ) else {
                    gaps.append(GapName(from: train.stops[fromIndex].name, to: train.stops[toIndex].name))
                    index += 1
                    continue
                }
                if plan.requiresConfirmation {
                    return Advance(train: train, repaired: repaired, gaps: gaps, pause: Pause(
                        fromVisitID: step.fromVisitID, toVisitID: step.toVisitID,
                        choices: [choice], remaining: Array(steps[(index + 1)...])))
                }
                train = plan.updatedTrain
                repaired += 1
                index += 1
            case .ambiguous(let choices):
                return Advance(train: train, repaired: repaired, gaps: gaps, pause: Pause(
                    fromVisitID: step.fromVisitID, toVisitID: step.toVisitID,
                    choices: choices, remaining: Array(steps[(index + 1)...])))
            case .none:
                gaps.append(GapName(from: train.stops[fromIndex].name, to: train.stops[toIndex].name))
                index += 1
            }
        }
        return Advance(train: train, repaired: repaired, gaps: gaps, pause: nil)
    }

    static func summary(
        repaired: Int, needsChoice: Int, gaps: [GapName],
        text: (String, [String: Localization.Param]) -> String
    ) -> String {
        var lines = [text("ios.route.repairSummary", [
            "repaired": .number(Double(repaired)),
            "choice": .number(Double(needsChoice)),
        ])]
        for gap in gaps {
            lines.append(text("ios.route.noSurveyedConnection", [
                "from": .string(gap.from),
                "to": .string(gap.to),
            ]))
        }
        return lines.joined(separator: "\n")
    }

    private static func name(_ id: UUID, in train: Train) -> String {
        train.stops.first { $0.routeEditing?.visitID == id }?.name ?? ""
    }
}
