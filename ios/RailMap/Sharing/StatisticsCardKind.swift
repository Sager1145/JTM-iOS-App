import Foundation

/// Stable identities, titles and symbols for dashboard cards in the share composer.
enum StatisticsCardKind: String, CaseIterable, Identifiable, Sendable {
    case recordTicket, dailyTicket, rhythm, distance, time, coverage, service
    case stations, operators, routes, topSegments, regions, lineDetail
    case rides

    var id: String { rawValue }
    static let standardOrder = allCases.filter { $0 != .rides }
    static let compactOrder: [StatisticsCardKind] = [.distance, .time, .coverage, .rides]
    var supportsCompactShapes: Bool { Self.compactOrder.contains(self) }
    var widgetShapes: [CardShape] {
        if self == .distance || self == .time { return [.strip] + CardShape.standardShapes }
        return supportsCompactShapes ? [.mini, .strip] + CardShape.standardShapes : CardShape.standardShapes
    }
    var localizationKey: String { "ios.stats.card.\(rawValue)" }
    var fallbackTitle: String {
        switch self {
        case .recordTicket: "Record ticket"
        case .dailyTicket: "Daily ticket"
        case .rhythm: "Travel rhythm"
        case .distance: "Longest trip"
        case .time: "Longest time"
        case .coverage: "Coverage"
        case .service: "Service mix"
        case .stations: "Visited stations"
        case .operators: "Ridden operators"
        case .routes: "Ridden routes"
        case .topSegments: "Most ridden segment"
        case .regions: "Regions"
        case .lineDetail: "Line coverage"
        case .rides: "Rides"
        }
    }
    var systemImage: String {
        switch self {
        case .recordTicket, .dailyTicket: "ticket"
        case .rhythm: "chart.bar"
        case .distance: "ruler"
        case .time: "clock"
        case .coverage: "percent"
        case .service: "tram"
        case .stations: "mappin"
        case .operators: "building.2"
        case .routes, .topSegments, .lineDetail: "point.topleft.down.to.point.bottomright.curvepath"
        case .regions: "map"
        case .rides: "tram.fill"
        }
    }
}

