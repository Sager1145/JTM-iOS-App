import RailCore
import RailPresentation
import SwiftUI
import UIKit

enum JourneyShareKind: String, CaseIterable, Identifiable {
    case full, basic
    var id: String { rawValue }
}

/// Both modes keep their own measured row height. No station is placed at a
/// fixed coordinate on a compressed route diagram, and no list is truncated.
@MainActor
enum JourneyPoster {
    struct Block {
        enum Style { case title, heading, body, stop, importantStop }
        var text: String
        var style: Style = .body
    }

    struct File {
        let url: URL
        let image: UIImage
        let text: String
        let kind: JourneyShareKind
    }

    static func blocks(
        train: Train, kind: JourneyShareKind, localization: AppLocalization,
        routeText: String
    ) -> [Block] {
        let l = localization
        var result = [Block(text: train.number, style: .title)]
        func field(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            result.append(Block(text: label + ": " + value))
        }
        func station(_ name: String, _ code: String?) -> String {
            let translated = l.stationName(name, in: train, code: code)
            return translated == name ? name : translated + " (" + name + ")"
        }
        // Preserve 24+ hour service notation while spelling out its actual day.
        func time(_ raw: String?) -> String? {
            guard let raw, !raw.isEmpty else { return nil }
            guard let date = train.date, case .valid(_, let clock) = EditorTime.parseTime(raw),
                  clock.dayOffset > 0, let day = Dates.addDays(date, clock.dayOffset)
            else { return raw }
            return raw + " (" + day + ")"
        }
        field(l.countryText("field.company", fallback: "Operator"),
              train.company ?? JourneyBranding.operatorLabels(of: train).joined(separator: " / "))
        field(l.countryText("field.trainType", fallback: "Train type"), train.trainType)
        field(l.journeyShareText("date"), train.date ?? l.journeyShareText("undated"))
        if let english = train.numberEn, !english.isEmpty, english != train.number {
            result.append(Block(text: english))
        }
        if !routeText.isEmpty { result.append(Block(text: routeText)) }

        let departure = l.countryText("popup.departure", fallback: "Departure")
        let arrival = l.countryText("popup.arrival", fallback: "Arrival")
        let first = train.stops.first(where: { $0.stopType == "origin" }) ?? train.stops.first
        let last = train.stops.last(where: { $0.stopType == "destination" }) ?? train.stops.last
        result.append(Block(text: departure + " · " + station(train.origin, train.originStationCode)
                            + "\n" + (time(first?.departure ?? first?.arrival) ?? "—"), style: .importantStop))
        result.append(Block(text: arrival + " · " + station(train.destination, train.destinationStationCode)
                            + "\n" + (time(last?.arrival ?? last?.departure) ?? "—"), style: .importantStop))

        result.append(Block(text: l.journeyShareText(kind == .full ? "timeline" : "stops"), style: .heading))
        let legs = JourneyServiceSections.legs(of: train)
        let changes = Set(legs.dropFirst().map(\.fromStopIndex))
        let indices = train.stops.indices.filter { kind == .full || train.stops[$0].stopType != "pass_through" }
        if indices.isEmpty { result.append(Block(text: l.journeyShareText("noStops"))) }
        for index in indices {
            let stop = train.stops[index]
            var lines = [station(stop.name, stop.n02StationCode)]
            var timing: [String] = []
            if let value = time(stop.arrival) { timing.append(arrival + " " + value) }
            if let value = time(stop.departure) { timing.append(departure + " " + value) }
            if !timing.isEmpty { lines.append(timing.joined(separator: " · ")) }
            // Actual observations are personal record details, exclusive to full sharing.
            if kind == .full {
                for (label, planned, actual) in [
                    ("ios.editor.actualArrival", stop.arrival, stop.actualArrival),
                    ("ios.editor.actualDeparture", stop.departure, stop.actualDeparture),
                ] {
                    if let actualTime = time(actual) {
                        let status = StopTimingStatus.localizedLabel(scheduled: planned, actual: actual, localization: l)
                        lines.append(l.editorText(label) + " " + actualTime
                                     + (status.map { " · " + $0 } ?? ""))
                    }
                }
            }
            if let platform = stop.platformNumber {
                lines.append(l.countryText("table.platform", fallback: "Platform") + " \(platform)")
            }
            if stop.stopType != "passenger_stop" {
                lines.append(l.countryText("stoptype.\(stop.stopType)", fallback: stop.stopType))
            }
            if train.journeyClock.crossesTimeZones {
                lines.append(l.journeyShareText("timeZone") + ": "
                             + l.journeyText(train.journeyClock.clock(atStopIndex: index).name))
            }
            if kind == .full {
                let ridden = l.editorText(stop.rideSegment ? "ios.detail.ridden" : "ios.detail.notRidden")
                if stop.stopType != "passenger_stop", let last = lines.indices.last {
                    lines[last] += " · " + ridden
                } else { lines.append(ridden) }
            }
            // Endpoints and recorded service/line changes are emphasised without
            // inventing an importance ranking for the other passenger stops.
            let important = stop.stopType == "passenger_stop" || index == 0
                || index == train.stops.count - 1 || changes.contains(index)
            result.append(Block(text: lines.joined(separator: "\n"), style: important ? .importantStop : .stop))
        }
        guard kind == .full else { return result }

        result.append(Block(text: l.editorText("ios.detail.service"), style: .heading))
        field(l.editorText("ios.editor.vehicleType"), train.vehicleType)
        field(l.countryText("field.direction", fallback: "Direction"), train.direction)
        field(l.editorText("ios.ai.notes"), train.notes)
        field(l.groupText("title"), train.journeyGroup?.name)
        field(l.text("ios.recordedStops", fallback: "Recorded stops"), String(train.stops.count))
        let confirmation: String = switch RideLedger.confirmation(of: train) {
        case .ridden: "ios.detail.riddenYes"
        case .partly: "ios.detail.riddenPartly"
        case .notRidden: "ios.detail.riddenNo"
        }
        field(l.editorText("ios.detail.riddenState"), l.editorText(confirmation))
        field(l.text("ios.visibility", fallback: "Visibility"), l.countryText(
            train.visible == false ? "state.hidden" : "state.shown", fallback: train.visible == false ? "Hidden" : "Shown"))
        let status = RideStatusCenter.shared.status(forTrainID: train.id)
        let stateKey: String = switch status {
        case .pendingConfirmation: "ios.routeGuide.pending"
        case .unknown: "ios.route.preparing"
        case .resolving: "ios.route.resolving"
        case .resolved: "ios.route.resolved"
        case .needsReview: "ios.route.needsReview"
        case .unavailable: "ios.route.unavailable"
        case .noRoute: "ios.journey.noRiddenSection"
        }
        result.append(Block(text: status == .pendingConfirmation ? l.editorText(stateKey)
            : stateKey.hasPrefix("ios.route.") ? l.editorText(stateKey) : l.journeyText(stateKey), style: .heading))
        if case .needsReview(_, _, let gaps) = status {
            for gap in gaps { result.append(Block(text: (gap.from ?? "?") + " → " + (gap.to ?? "?"))) }
        }
        if case .unavailable(_, let reason) = status, let reason, !reason.isEmpty {
            result.append(Block(text: reason))
        }
        result.append(Block(text: l.editorText("ios.detail.advanced"), style: .heading))
        field(l.countryText("field.id", fallback: "Identifier"), train.id)
        let policyKey = switch train.routePolicy?.institutionFilterMode {
        case "hard": "ios.editor.hardConstraint"
        case "soft": "ios.editor.softPreference"
        default: "ios.editor.automatic"
        }
        field(l.text("ios.routePolicy", fallback: "Route policy"), l.editorText(policyKey))
        result.append(Block(text: l.editorText("ios.detail.routeSections", [
            "count": .number(Double(train.routeSections?.count ?? 0))]), style: .heading))
        if let sections = train.routeSections, !sections.isEmpty {
            for (index, section) in sections.enumerated() {
                let from = section.from ?? (index < train.stops.count ? train.stops[index].name : section.fromN02StationCode ?? "?")
                let to = section.to ?? (index + 1 < train.stops.count ? train.stops[index + 1].name : section.toN02StationCode ?? "?")
                var lines = ["\(index + 1). " + station(from, section.fromN02StationCode) + " → " + station(to, section.toN02StationCode)]
                lines += [section.number, section.name].compactMap { $0 }.filter { !$0.isEmpty }
                lines += (section.lineNames ?? []) + (section.operatorNames ?? [])
                result.append(Block(text: lines.joined(separator: "\n")))
            }
        } else { result.append(Block(text: l.editorText("ios.detail.noRouteSections"))) }
        return result
    }

    private struct Row {
        var block: Block
        var attributedText: NSAttributedString
        var height: CGFloat
    }

    /// A single tall bitmap, with a bounded raster size rather than clipping
    /// the tail or splitting a long journey into separate files.
    static func render(
        train: Train, kind: JourneyShareKind, localization: AppLocalization,
        routeText: String
    ) async throws -> File {
        let blocks = blocks(train: train, kind: kind, localization: localization, routeText: routeText)
        let columnWidth: CGFloat = 440
        let textWidth: CGFloat = columnWidth - 80
        let ink = UIColor(red: 0.12, green: 0.17, blue: 0.22, alpha: 1)
        let accent = UIColor(railHex: train.style?.color ?? "#d9364f") ?? .systemRed
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 4
        let rows = blocks.map { block in
            let size: CGFloat = switch block.style {
            case .title: 28
            case .heading: 20
            case .importantStop: 18
            case .body, .stop: 16
            }
            let weight: UIFont.Weight = switch block.style {
            case .title, .heading, .importantStop: .semibold
            case .body, .stop: .regular
            }
            let attributed = NSAttributedString(string: block.text, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: ink, .paragraphStyle: paragraph,
            ])
            let bounds = attributed.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return Row(block: block, attributedText: attributed, height: ceil(bounds.height) + 4)
        }
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height + 28 }
        // Very long records use sequential columns on the SAME image. This
        // preserves readable lettering within the bitmap budget, even when
        // hundreds of pass-through stations and route sections are recorded.
        let columns = min(4, max(1, Int(ceil(totalHeight / 7_000))))
        let largestGroup = rows.enumerated().map { index, row in
            row.height + 28 + (row.block.style == .heading && index + 1 < rows.count
                ? rows[index + 1].height + 28 : 0)
        }.max() ?? 0
        let columnHeight = ceil(totalHeight / CGFloat(columns)) + largestGroup + 100
        var placements: [(row: Row, column: Int, y: CGFloat)] = []
        var column = 0
        var y: CGFloat = 56
        for (index, row) in rows.enumerated() {
            let needed = row.height + 28 + (row.block.style == .heading && index + 1 < rows.count
                ? rows[index + 1].height + 28 : 0)
            if y > 56, y + needed > columnHeight - 32, column + 1 < columns {
                column += 1
                y = 56
            }
            placements.append((row, column, y))
            y += row.height + 28
        }
        let width = columnWidth * CGFloat(columns)
        let height = (placements.map { $0.y + $0.row.height }.max() ?? 56) + 40
        let scale = min(3, sqrt(16_000_000 / (width * height)), 20_000 / height)
        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
        for index in 0..<columns {
            let label = NSAttributedString(string: "JAPAN TRAIN MAP" + (columns > 1 ? " · \(index + 1)/\(columns) →" : ""), attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: accent,
            ])
            label.draw(at: CGPoint(x: CGFloat(index) * columnWidth + 40, y: 24))
        }
        for placement in placements {
            let row = placement.row
            let x = CGFloat(placement.column) * columnWidth
            let y = placement.y
            let rect = CGRect(x: x + 24, y: y - 8, width: columnWidth - 48, height: row.height + 16)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            if row.block.style == .stop || row.block.style == .importantStop {
                accent.setFill()
                UIBezierPath(roundedRect: CGRect(x: x + 28, y: y, width: 3, height: row.height), cornerRadius: 1.5).fill()
            }
            row.attributedText.draw(with: CGRect(x: x + 40, y: y, width: textWidth, height: row.height),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        UIGraphicsPopContext()
        try Task.checkCancellation()
        guard let bitmap = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let image = UIImage(cgImage: bitmap, scale: scale, orientation: .up)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rail-journey-\(UUID().uuidString).png")
        // Encoding and file I/O do not block the preview's UI actor.
        let written = await Task.detached(priority: .userInitiated) {
            guard let data = UIImage(cgImage: bitmap).pngData() else { return false }
            do { try data.write(to: url, options: .atomic); return true }
            catch { return false }
        }.value
        try Task.checkCancellation()
        guard written else { throw CocoaError(.fileWriteUnknown) }
        return File(url: url, image: image, text: blocks.map(\.text).joined(separator: "\n\n"), kind: kind)
    }
}

struct JourneyShareView: View {
    let train: Train
    @Environment(AppLocalization.self) private var localization
    @Environment(RailNetworkStore.self) private var network: RailNetworkStore?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: JourneyShareKind = .full
    @State private var file: JourneyPoster.File?
    @State private var failed = false
    @State private var retry = 0
    @State private var showsActivity = false
    @State private var showsZoom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker(localization.journeyShareText("title"), selection: $kind) {
                        ForEach(JourneyShareKind.allCases) { kind in
                            Text(localization.journeyShareText(kind.rawValue)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("journeyShareKindPicker")
                    Text(localization.journeyShareText(kind == .full ? "fullNote" : "basicNote"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let file, file.kind == kind {
                        Image(uiImage: file.image)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(localization.journeyShareText("preview"))
                            .accessibilityValue(file.text)
                            .accessibilityIdentifier("journeySharePreview-0")
                            .onTapGesture { showsZoom = true }
                    } else if failed {
                        Text(localization.journeyShareText("failed"))
                        Button(localization.journeyShareText("retry")) { retry += 1 }
                    } else {
                        ProgressView(localization.journeyShareText("preparing"))
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("journeyShareSheet")
            .navigationTitle(localization.journeyShareText("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.done", fallback: "Done")) { dismiss() }
                        .accessibilityIdentifier("journeyShareCloseButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(localization.text("ios.share", fallback: "Share"), systemImage: "square.and.arrow.up") {
                    showsActivity = true
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity).railMinimumTouchTarget()
                .disabled(file == nil || file?.kind != kind)
                .accessibilityIdentifier("journeyShareSendButton")
                .padding(16).background(.bar)
            }
            .sheet(isPresented: $showsActivity) {
                if let file, file.kind == kind { JourneyActivitySheet(file: file) }
            }
            .fullScreenCover(isPresented: $showsZoom) {
                if let file {
                    NavigationStack {
                        JourneyImageZoom(image: file.image)
                            .navigationTitle(localization.journeyShareText("preview"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(localization.text("ios.done", fallback: "Done")) { showsZoom = false }
                                }
                            }
                    }
                }
            }
            .task(id: "\(kind.rawValue)-\(retry)-\(localization.language.rawValue)") {
                file = nil
                failed = false
                let route = JourneyBranding.routeText(of: train,
                    detected: RideStatusCenter.shared.traversedLines(forTrainID: train.id), badges: network?.badges)
                do {
                    let rendered = try await JourneyPoster.render(train: train, kind: kind,
                        localization: localization, routeText: route)
                    try Task.checkCancellation()
                    file = rendered
                } catch is CancellationError { }
                catch { failed = true }
            }
        }
    }
}

private struct JourneyActivitySheet: UIViewControllerRepresentable {
    let file: JourneyPoster.File
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = file.kind == .full ? [file.url, file.text] : [file.url]
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

/// Inspect lettering at full size before sending a long, single image.
private struct JourneyImageZoom: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> JourneyZoomScrollView { JourneyZoomScrollView(image: image) }
    func updateUIView(_ view: JourneyZoomScrollView, context: Context) { }
}

private final class JourneyZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var fitted = false

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)
        contentSize = image.size
        delegate = self
        backgroundColor = .secondarySystemBackground
        maximumZoomScale = 4
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, !fitted else { return }
        fitted = true
        minimumZoomScale = min(1, bounds.width / imageView.bounds.width)
        zoomScale = minimumZoomScale
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}
