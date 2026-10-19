import Foundation
import CoreGraphics

/// A tiny screen-space collision index for labels the app owns.
///
/// MapKit's annotation collision pass also competes with the basemap's labels.
/// Giving our station names a priority low enough to collide made every name in
/// a dense city disappear behind Apple's road labels; making them `.required`
/// kept the names, but also disabled collision handling between our own names.
/// This grid separates those two questions: it thins only JTM labels before
/// they reach MapKit, then the accepted labels can remain stable above the map.
struct MapLabelCollisionGrid {
    private struct Cell: Hashable {
        let column: Int
        let row: Int
    }

    private static let cellSize: CGFloat = 96
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 6
    private var boxesByCell: [Cell: [CGRect]] = [:]

    mutating func insertIfClear(_ box: CGRect) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let padded = box.insetBy(
            dx: -Self.horizontalPadding, dy: -Self.verticalPadding)
        let columns = cellRange(from: padded.minX, through: padded.maxX)
        let rows = cellRange(from: padded.minY, through: padded.maxY)

        for column in columns {
            for row in rows {
                let cell = Cell(column: column, row: row)
                if boxesByCell[cell, default: []].contains(where: {
                    $0.intersects(padded)
                }) {
                    return false
                }
            }
        }
        for column in columns {
            for row in rows {
                boxesByCell[Cell(column: column, row: row), default: []].append(padded)
            }
        }
        return true
    }

    /// Endpoint cards stay visible even when two of them overlap. Reserve both
    /// boxes so later station names cannot be admitted on top of either card.
    mutating func reserve(_ box: CGRect) {
        guard box.width > 0, box.height > 0 else { return }
        let padded = box.insetBy(
            dx: -Self.horizontalPadding, dy: -Self.verticalPadding)
        for column in cellRange(from: padded.minX, through: padded.maxX) {
            for row in cellRange(from: padded.minY, through: padded.maxY) {
                boxesByCell[Cell(column: column, row: row), default: []].append(padded)
            }
        }
    }

    private func cellRange(from lower: CGFloat, through upper: CGFloat) -> ClosedRange<Int> {
        Int(floor(lower / Self.cellSize))...Int(floor(upper / Self.cellSize))
    }
}
