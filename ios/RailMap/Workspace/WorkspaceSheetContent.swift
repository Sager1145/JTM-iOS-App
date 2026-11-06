import RailCore
import RailPresentation
import SwiftUI

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
        case .utility(let destination): "utility:\(destination.rawValue)"
        }
    }
}

