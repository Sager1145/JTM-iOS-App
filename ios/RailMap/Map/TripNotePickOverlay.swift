import RailCore
import SwiftUI

/// The chrome of a trip-note place pick: a fixed centre pin the reader pans
/// the map under, a banner saying what it is over, and a bar to confirm, use
/// the device's location, choose a stop, or cancel.
///
/// Laid out in the map view's own coordinates (the pin tip at
/// ``TripNotePickFeedback/pinPoint``), which is why everything here ignores
/// the safe area and places itself by the numbers the coordinator measured.
struct TripNotePickOverlay: View {
    let controller: RailMapController
    /// The trip's solved ride; nil until its route is drawn. Without it the
    /// pick still offers the station menu, and nothing else.
    let ride: RiddenRouteStore.DrawnRide?
    /// The trip's own stops (the itinerary's, not the ride's).
    let stops: [Stop]
    /// The trip's region code, for naming its stops.
    let region: String?
    /// How many rides the map is drawing during the pick, for UI tests.
    let visibleRideCount: Int

    @Environment(AppLocalization.self) private var localization: AppLocalization?
    @State private var alertKey: String?
    @State private var locating = false
    @ScaledMetric(relativeTo: .caption) private var bangSize: CGFloat = 14

    private static let amber = Color(red: 0.93, green: 0.56, blue: 0.00)

    var body: some View {
        let feedback = controller.tripNotePickFeedback
        ZStack(alignment: .top) {
            if let feedback {
                pin(snapped: feedback.anchor != nil)
                    .position(x: feedback.pinPoint.x, y: feedback.pinPoint.y - Self.pinHeight / 2)
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                banner(feedback)
                    .padding(.top, (feedback?.topInset ?? 0) + RailSpacing.s8)
                Spacer(minLength: 0)
                bar(feedback)
                    .padding(.bottom, feedback?.barBottom ?? RailSpacing.mapChromeInset)
            }
            .padding(.horizontal, RailSpacing.s16)
#if DEBUG
            Text("tripNotePickMode=on;visibleRides=\(visibleRideCount)")
                .font(.caption)
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityIdentifier("tripNotePickState")
#endif
        }
        .ignoresSafeArea()
        .onChange(of: controller.readerCameraMoves) { _, _ in alertKey = nil }
        // A new pick never inherits the last one's location message.
        .onChange(of: controller.tripNotePickRevision) { _, _ in alertKey = nil }
    }

    // MARK: pieces

    private static let pinHeight: CGFloat = 40

    private func pin(snapped: Bool) -> some View {
        let color = snapped ? Self.amber : Color(white: 0.55)
        return VStack(spacing: 0) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .overlay(Text("!").font(.system(size: bangSize, weight: .heavy)).foregroundStyle(.white))
            Rectangle()
                .fill(color)
                .frame(width: 3, height: Self.pinHeight - 24)
        }
        .frame(height: Self.pinHeight)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private func banner(_ feedback: TripNotePickFeedback?) -> some View {
        VStack(spacing: 2) {
            Text(text("ios.tripNotes.pick.title", fallback: "Move the map to place the note"))
                .font(.subheadline.weight(.semibold))
            Text(ride == nil
                 ? text("ios.tripNotes.pick.routePending",
                        fallback: "This trip's route isn't drawn yet. Choose a station.")
                 : feedback?.summary
                    ?? text("ios.tripNotes.pick.offLine", fallback: "Move the pin onto this trip's line"))
                .font(.footnote) // ui-token-ok: conditional colour
                .foregroundStyle(feedback?.anchor == nil ? .secondary : .primary)
            if let alertKey {
                RailStatusLabel(kind: .error, text: text(alertKey))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, RailSpacing.s12)
        .padding(.vertical, RailSpacing.s8)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RailRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tripNotePickBanner")
    }

    private func bar(_ feedback: TripNotePickFeedback?) -> some View {
        HStack(spacing: RailSpacing.s8) {
            Button(text("ios.cancel", fallback: "Cancel")) {
                controller.cancelTripNotePick()
            }
            .accessibilityIdentifier("tripNotePickCancel")

            if ride != nil {
                Button {
                    locate()
                } label: {
                    Label(text("ios.tripNotes.pick.myLocation", fallback: "My location"),
                          systemImage: "location.fill")
                }
                .disabled(locating)
                .accessibilityIdentifier("tripNotePickMyLocation")
            }

            Menu {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    Button(stopName(stop)) { pickStation(index) }
                }
            } label: {
                Label(text("ios.tripNotes.pick.station", fallback: "Station"), systemImage: "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .accessibilityIdentifier("tripNotePickStation")

            if ride != nil {
                Button(text("ios.tripNotes.pick.confirm", fallback: "Confirm")) {
                    if let anchor = feedback?.anchor { controller.finishTripNotePick(anchor) }
                }
                .buttonStyle(.railPrimary)
                .tint(Self.amber)
                .disabled(feedback?.anchor == nil)
                .accessibilityIdentifier("tripNotePickConfirm")
            }
        }
        .buttonStyle(.railSecondary)
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(RailSpacing.s8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RailRadius.control, style: .continuous))
    }

    // MARK: actions

    private func pickStation(_ index: Int) {
        guard let anchor = TripNoteGeometry.stationAnchor(stopIndex: index, stops: stops, ride: ride) else { return }
        controller.finishTripNotePick(anchor)
    }

    private func stopName(_ stop: Stop) -> String {
        // The base name, as the banner and the map captions show it; the
        // place-name form would append readings ("Tokyo (Tōkyō)").
        localization?.stationName(stop.name, code: stop.n02StationCode,
                                  region: region.flatMap(Region.init(rawValue:)))
            ?? stop.name
    }

    /// The only place the pick may ask for location permission.
    private func locate() {
        alertKey = nil
        locating = true
        let token = controller.tripNotePickToken()
        Task { @MainActor in
            let result = await controller.currentLocationOnce()
            locating = false
            // Stale: the pick ended or restarted, or the reader moved the map
            // since asking. Neither the camera nor an alert follows.
            guard controller.tripNotePickTokenIsCurrent(token) else { return }
            switch result {
            case .success(let location):
                guard let ride,
                      let anchor = TripNoteGeometry.anchor(
                        forLocation: Coordinate(lon: location.coordinate.longitude,
                                                lat: location.coordinate.latitude),
                        on: ride, maxMeters: 2_000, stationSnapMeters: 150),
                      let point = TripNoteGeometry.displayCoordinate(of: anchor, on: ride) else {
                    alertKey = "ios.tripNotes.location.tooFar"
                    return
                }
                controller.centerTripNotePick(on: point.clLocation, animated: true)
            case .failure(.refused):
                alertKey = "ios.tripNotes.location.denied"
            case .failure(.unavailable):
                alertKey = "ios.tripNotes.location.failed"
            }
        }
    }

    private func text(_ key: String, fallback: String? = nil) -> String {
        localization?.text(key, fallback: fallback) ?? fallback ?? key
    }
}

/// Title first, icon after: a "Station ▾" menu button.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RailSpacing.s4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
