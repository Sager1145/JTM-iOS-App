import RailCore
import RailPresentation
import SwiftUI

/// Every sheet the workspace can present over its resident chrome.
enum WorkspaceSheet: Identifiable {
    case detail(String)
    case importData
    case videoOptions
    case mapInfo
    case mapLayers
    case station(StationCard)
    case chooseRide([Train])
    case utility(UtilityDestination)

    var hidesWorkspaceMenu: Bool {
        if case .detail = self { return true }
        return false
    }

    var id: String {
        switch self {
        case .detail(let id): "detail:\(id)"
        case .importData: "import"
        case .videoOptions: "video"
        case .mapInfo: "info"
        case .mapLayers: "layers"
        case .station(let card): "station:\(card.id)"
        case .chooseRide(let trains): "choose:\(trains.map(\.id).joined(separator: ","))"
        case .utility(let destination): "utility:\(destination.rawValue)"
        }
    }
}

