import Foundation

/// Physical track direction and the direction of stored station order are
/// separate facts. Only source-backed package metadata restricts traversal.
public enum RailwayDirection {
    public static func allowedDirections(for line: CompactPackage.Line, intervalIndex: Int) -> [Int] {
        let traversal: [Int]
        switch line.permittedTraversal {
        case "forward": traversal = [1]
        case "reverse": traversal = [-1]
        default: traversal = [-1, 1]
        }
        guard let order = line.stationOrderDirection, ["up", "down"].contains(order) else { return traversal }
        var physical = line.alignmentDirection
        if physical != "up" && physical != "down" {
            physical = nil
            for pair in line.alignmentPairs where pair.direction == "up" || pair.direction == "down" {
                guard pair.with != line.id,
                      let start = line.stations.firstIndex(where: { $0.name == pair.from }),
                      let end = line.stations.firstIndex(where: { $0.name == pair.to }),
                      (min(start, end)..<max(start, end)).contains(intervalIndex) else { continue }
                physical = pair.direction
                break
            }
        }
        guard let physical else { return traversal }
        let sign = physical == order ? 1 : -1
        return traversal.filter { $0 == sign }
    }
}
