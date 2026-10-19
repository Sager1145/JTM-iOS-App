import CoreGraphics

/// Ticket-module shapes shared by the statistics dashboard and share composer.
enum CardShape: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case mini, strip, small, medium, tall, large

    static let standardShapes: [CardShape] = [.small, .medium, .tall, .large]
    var isCompact: Bool { self == .mini || self == .strip }

    var id: String { rawValue }

    var designSize: CGSize {
        switch self {
        case .mini: CGSize(width: 75.5, height: 75.5)
        case .strip: CGSize(width: 158, height: 75.5)
        case .small: CGSize(width: 158, height: 158)
        case .medium: CGSize(width: 233.5, height: 158)
        case .tall: CGSize(width: 158, height: 233.5)
        case .large: CGSize(width: 233.5, height: 233.5)
        }
    }

    var baseSpan: GridSpan {
        switch self {
        case .mini: GridSpan(columns: 1, rows: 1)
        case .strip: GridSpan(columns: 2, rows: 1)
        case .small: GridSpan(columns: 2, rows: 2)
        case .medium: GridSpan(columns: 3, rows: 2)
        case .tall: GridSpan(columns: 2, rows: 3)
        case .large: GridSpan(columns: 3, rows: 3)
        }
    }

    static func matching(_ span: GridSpan, preferred: CardShape) -> CardShape {
        let aspect = Double(span.columns) / Double(max(span.rows, 1))
        if preferred.isCompact { return aspect > 1.2 ? .strip : .mini }
        if aspect > 1.2 { return .medium }
        if aspect < 0.82 { return .tall }
        if preferred == .small || preferred == .large { return preferred }
        return min(span.columns, span.rows) <= 2 ? .small : .large
    }
}

struct CardSize: Hashable, Codable, Sendable {
    var shape: CardShape
    var scale: Int

    init(shape: CardShape, scale: Int = 1) {
        self.shape = shape
        self.scale = max(1, scale)
    }

    var span: GridSpan {
        GridSpan(
            columns: shape.baseSpan.columns * scale,
            rows: shape.baseSpan.rows * scale)
    }
}

extension StatisticsCardKind {
    var preferredWidgetShape: CardShape {
        switch self {
        case .recordTicket, .dailyTicket, .rhythm, .distance, .service, .regions:
            .medium
        case .time, .operators, .routes, .rides:
            .small
        case .stations, .topSegments:
            .tall
        case .coverage, .lineDetail:
            .large
        }
    }
}
