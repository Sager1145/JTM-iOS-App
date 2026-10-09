import MapKit
import RailCore
import RailPresentation
import SwiftUI
import UIKit

/// A rendered share image kept in memory for preview and on disk for ShareLink.
struct StatisticsShareFile: Identifiable, Equatable {
    var url: URL
    var image: UIImage
    var accessibilityLabelKey: String = "ios.stats.shareImageLabel"
    var titleKey: String = "ios.stats.shareTitle"
    var id: String { url.absoluteString }
}

/// A fresh map for the passport's selected date and region. The caller passes
/// exactly the rides counted by that scope, so the image never inherits the
/// reader's unrelated pan or zoom on the live workspace map.
enum StatisticsMapSnapshot {
    private struct SnapshotBox: @unchecked Sendable {
        let value: MKMapSnapshotter.Snapshot?
    }

    @MainActor
    static func render(
        rides: [RiddenRouteStore.DrawnRide],
        fallback: MKCoordinateRegion?,
        colorScheme: ColorScheme,
        size: CGSize = CGSize(width: 736, height: 736),
        zoom: Double = 1,
        name: String? = nil
    ) async -> UIImage? {
        let segments = rides.flatMap(\.segments).filter { !$0.boundingRect.isNull }
        let bounds = segments.reduce(MKMapRect.null) { $0.union($1.boundingRect) }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let baseRect: MKMapRect?
        if let fallback {
            baseRect = mapRect(for: fallback)
        } else if !bounds.isNull {
            baseRect = bounds
        } else {
            return nil
        }
        if let baseRect {
            options.mapRect = fitted(baseRect, aspect: size.width / max(size.height, 1), zoom: zoom)
        }

        let snapshotSize = options.size
        let snapshotter = MKMapSnapshotter(options: options)
        let result: SnapshotBox = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                snapshotter.start(with: .main) { snapshot, _ in
                    continuation.resume(returning: SnapshotBox(value: snapshot))
                }
            }
        } onCancel: {
            snapshotter.cancel()
        }
        guard let snapshot = result.value, !Task.isCancelled else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: snapshotSize, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for ride in rides {
                guard let color = UIColor(railHex: ride.colorHex) else { continue }
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(max(2, min(size.width, size.height) / 180))
                for segment in ride.segments where segment.coordinates.count > 1 {
                    let points = segment.coordinates.map {
                        snapshot.point(for: CLLocationCoordinate2D(
                            latitude: $0.lat, longitude: $0.lon))
                    }
                    cg.beginPath()
                    cg.move(to: points[0])
                    for point in points.dropFirst() { cg.addLine(to: point) }
                    cg.strokePath()
                }
            }
            if let name {
                let font = UIFont.systemFont(ofSize: max(12, min(size.width, size.height) / 24),
                                             weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.label,
                ]
                let measured = (name as NSString).size(withAttributes: attributes)
                let inset = max(10, min(size.width, size.height) / 40)
                let rect = CGRect(x: inset, y: inset,
                                  width: measured.width + inset * 1.4,
                                  height: measured.height + inset)
                cg.setFillColor((colorScheme == .dark
                    ? UIColor.black.withAlphaComponent(0.76)
                    : UIColor.systemBackground.withAlphaComponent(0.86)).cgColor)
                cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath)
                cg.fillPath()
                (name as NSString).draw(at: CGPoint(x: rect.minX + inset * 0.7,
                                                    y: rect.minY + inset * 0.5),
                                        withAttributes: attributes)
            }
        }
    }

    private static func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
        let northWest = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let southEast = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(x: min(northWest.x, southEast.x), y: min(northWest.y, southEast.y),
                         width: abs(southEast.x - northWest.x),
                         height: abs(southEast.y - northWest.y))
    }

    private static func fitted(_ rect: MKMapRect, aspect: CGFloat, zoom: Double) -> MKMapRect {
        var width = max(rect.width, 1_000_000)
        var height = max(rect.height, 1_000_000)
        let current = width / height
        if current < aspect { width = height * aspect } else { height = width / aspect }
        let scale = 1 / min(max(zoom, 0.75), 2)
        return MKMapRect(x: rect.midX - width * scale / 2, y: rect.midY - height * scale / 2,
                         width: width * scale, height: height * scale)
    }
}

/// What the reader sees before anything is shared: the picture itself, and the
/// system's own share button under it.
///
/// A preview rather than going straight to the share sheet, for the reason
/// §5.6 gives the video export its options screen — sharing is the irreversible
/// half, and the reader should have seen what they are about to send before
/// they choose where it goes.
struct StatisticsShareView: View {
    @Environment(AppLocalization.self) private var localization

    var file: StatisticsShareFile
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: file.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: RailStyle.cardCornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: RailStyle.cardCornerRadius, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    }
                    .padding(16)
                    .accessibilityLabel(
                        Text(
                            localization.statsText(file.accessibilityLabelKey)))
            }
            .navigationTitle(localization.statsText(file.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: file.url) {
                    Label(
                        localization.text("ios.share", fallback: "Share"),
                        systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .railMinimumTouchTarget()
                .padding(16)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.done", fallback: "Done"), action: onClose)
                        .accessibilityIdentifier("statisticsShareCloseButton")
                }
            }
            // Identified rather than found by label: `ConsoleSweepTests` walks
            // this surface, and the label is the reader's language.
            .accessibilityIdentifier("statisticsShareSheet")
        }
    }
}
