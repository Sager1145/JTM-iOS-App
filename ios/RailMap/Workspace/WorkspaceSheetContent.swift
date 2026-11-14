import RailCore
import RailPresentation
import SwiftUI

/// A network line the reader tapped on the map: the row the line card shows and
/// the region its package belongs to.
struct NetworkLineTarget: Identifiable, Equatable {
    let row: StationDisplay.PopupRow
    let region: Region
    var id: String { "\(region.code)|\(row.lineID)" }

    init(_ line: RailNetworkStore.DrawnLine) {
        let logo = OperatorBranding.logoForLine(
            OperatorBranding.Line(lineId: line.lineID, operator: line.operatorName))
        row = StationDisplay.PopupRow(
            lineID: line.lineID,
            company: OperatorBranding.companyFor(operator: line.operatorName, lineName: line.name),
            label: line.nameRoma.flatMap { $0.isEmpty ? nil : $0 }.map { "\(line.name) (\($0))" } ?? line.name,
            color: line.colorHex, logo: logo,
            logoNeedsDarkMatte: OperatorBranding.logoNeedsDarkMatte(logo),
            operatorName: line.operatorName)
        region = line.region
    }
}

/// Every sheet the workspace can present over its resident chrome.
enum WorkspaceSheet: Identifiable {
    case detail(String)
    case importData
    /// A transfer-guide screenshot, from the Add trip menu (pass 3).
    case transferGuide
    /// Hide regions, years or months (the scope filter's second half).
    case hideTrips
    case mapInfo
    case mapLayers
    case station(StationCard)
    case chooseRide([Train])
    case line(NetworkLineTarget)
    case chooseLine([NetworkLineTarget])
    case utility(UtilityDestination)

    var hidesWorkspaceMenu: Bool {
        if case .detail = self { return true }
        return false
    }

    var id: String {
        switch self {
        case .detail(let id): "detail:\(id)"
        case .importData: "import"
        case .transferGuide: "guide"
        case .hideTrips: "hideTrips"
        case .mapInfo: "info"
        case .mapLayers: "layers"
        case .station(let card): "station:\(card.id)"
        case .chooseRide(let trains): "choose:\(trains.map(\.id).joined(separator: ","))"
        case .line(let target): "line:\(target.id)"
        case .chooseLine(let targets): "chooseLine:\(targets.map(\.id).joined(separator: ","))"
        case .utility(let destination): "utility:\(destination.rawValue)"
        }
    }
}

