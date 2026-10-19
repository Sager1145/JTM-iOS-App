import RailCore
import RailPresentation
import SwiftUI

struct ServiceSectionSummary: View {
    @Environment(AppLocalization.self) private var localization
    let leg: JourneyServiceSections.Leg
    let train: Train

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(localization.sectionEndpoint(name: leg.from, code: leg.fromStationCode, in: train, stopIndex: leg.fromStopIndex)) → \(localization.sectionEndpoint(name: leg.to, code: leg.toStationCode, in: train, stopIndex: leg.toStopIndex))")
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
                value: leg.info.number ?? localization.text("ios.editor.sectionNumberUnknown"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
