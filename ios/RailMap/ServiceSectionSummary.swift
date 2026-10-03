import RailCore
import RailPresentation
import SwiftUI

struct ServiceSectionSummary: View {
    @Environment(AppLocalization.self) private var localization
    let leg: JourneyServiceSections.Leg
    let train: Train

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(station(at: leg.fromStopIndex)) → \(station(at: leg.toStopIndex))")
                .font(.subheadline.weight(.semibold))
            if !leg.info.operatorNames.isEmpty {
                Text(leg.info.operatorNames.joined(separator: " · "))
                    .font(.subheadline)
            }
            if !leg.info.lineNames.isEmpty {
                Text(leg.info.lineNames.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let name = leg.info.name {
                Text(name).font(.subheadline)
            }
            LabeledContent(
                localization.countryText("field.number", fallback: "Train number"),
                value: leg.info.number ?? localization.editorText("ios.editor.sectionNumberUnknown"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func station(at index: Int) -> String {
        guard train.stops.indices.contains(index) else {
            return localization.editorText("ios.route.unnamedStation")
        }
        let stop = train.stops[index]
        return localization.stationName(stop.name, in: train, code: stop.n02StationCode)
    }
}
