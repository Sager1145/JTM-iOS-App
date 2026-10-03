import CoreGraphics
import Foundation

/// A projective map from a local Mercator plane to the displayed viewport.
/// Inputs come from public annotation views; this owns only the fitted math,
/// never the map camera, rail geometry, or annotation lifetime.
nonisolated struct MapRailHomography {
    struct Sample {
        let source: CGPoint
        let displayed: CGPoint
    }
    private let origin: CGPoint
    private let scale: CGFloat
    private let coefficients: [Double]

    static func fit(_ samples: [Sample]) -> Self? {
        guard samples.count >= 4,
            samples.allSatisfy({ $0.source.x.isFinite && $0.source.y.isFinite
                && $0.displayed.x.isFinite && $0.displayed.y.isFinite }) else { return nil }
        let origin = CGPoint(
            x: samples.reduce(0) { $0 + $1.source.x } / CGFloat(samples.count),
            y: samples.reduce(0) { $0 + $1.source.y } / CGFloat(samples.count))
        let scale = samples.map { hypot($0.source.x - origin.x, $0.source.y - origin.y) }.max() ?? 0
        guard scale > 0 else { return nil }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        func add(_ row: [Double], _ result: Double) {
            for i in 0..<8 {
                for j in 0..<8 { matrix[i][j] += row[i] * row[j] }
                matrix[i][8] += row[i] * result
            }
        }
        for sample in samples {
            let x = Double((sample.source.x - origin.x) / scale)
            let y = Double((sample.source.y - origin.y) / scale)
            let u = Double(sample.displayed.x), v = Double(sample.displayed.y)
            add([x, y, 1, 0, 0, 0, -u * x, -u * y], u)
            add([0, 0, 0, x, y, 1, -v * x, -v * y], v)
        }
        for column in 0..<8 {
            guard let pivot = (column..<8).max(by: {
                abs(matrix[$0][column]) < abs(matrix[$1][column])
            }), abs(matrix[pivot][column]) > 1e-10 else { return nil }
            matrix.swapAt(column, pivot)
            let divisor = matrix[column][column]
            for j in column..<9 { matrix[column][j] /= divisor }
            for row in 0..<8 where row != column {
                let factor = matrix[row][column]
                for j in column..<9 { matrix[row][j] -= factor * matrix[column][j] }
            }
        }
        let coefficients = matrix.map { $0[8] }
        guard coefficients.allSatisfy(\.isFinite) else { return nil }
        return Self(origin: origin, scale: scale, coefficients: coefficients)
    }

    func project(_ point: CGPoint) -> CGPoint? {
        let x = Double((point.x - origin.x) / scale)
        let y = Double((point.y - origin.y) / scale)
        let denominator = coefficients[6] * x + coefficients[7] * y + 1
        guard denominator.isFinite, abs(denominator) > 1e-10 else { return nil }
        let result = CGPoint(
            x: (coefficients[0] * x + coefficients[1] * y + coefficients[2]) / denominator,
            y: (coefficients[3] * x + coefficients[4] * y + coefficients[5]) / denominator)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }
}
