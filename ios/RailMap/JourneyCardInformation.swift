import RailCore
import RailPresentation
import SwiftUI

/// Shared identity: the title stays to the left of the same bounded logo.
struct JourneyCardHeading: View {
    let train: Train
    var showsDate = true
    @Environment(DisplaySettings.self) private var display: DisplaySettings?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                serviceTitle
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("journeyServiceName-\(train.id)")
                if showsDate, let date = train.date, !date.isEmpty {
                    Text(date)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RouteLogoSquare(train: train, side: WorkspaceMenuMetrics.journeyLogoSide)
                .accessibilityIdentifier("journeyLogo-\(train.id)")
        }
    }

    private var serviceTitle: Text {
        let name = JourneyTitle.cardName(train, showsTranslation: display?.showJourneyTranslations == true)
        let title = Text(verbatim: name.primary)
        guard let original = name.original else { return title }
        return title + Text(verbatim: " (\(original))").font(.caption2)
            .fontWeight(.regular).foregroundStyle(.secondary)
    }
}

/// The card and the opened menu use identical arrows, clocks and annotations.
struct JourneyStationInformation: View {
    let train: Train
    let stop: Stop
    let index: Int
    @Environment(AppLocalization.self) private var localization
    @Environment(DisplaySettings.self) private var display: DisplaySettings?
    @ScaledMetric(relativeTo: .title2) private var timeSize: CGFloat = 28

    var body: some View {
        let planned = index == 0 ? stop.departure ?? stop.arrival : stop.arrival ?? stop.departure
        let actual = index == 0 ? stop.actualDeparture ?? stop.actualArrival
            : stop.actualArrival ?? stop.actualDeparture
        let shown = displayTime(actual ?? planned)
        VStack(alignment: .leading, spacing: 3) {
            Label {
                stationTitle
            } icon: {
                Image(systemName: index == 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
            }
            .font(.footnote.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(shown.time)
                    .font(.system(size: timeSize, weight: .semibold))
                    .monospacedDigit()
                if let actual, let planned, actual != planned {
                    Text(displayTime(planned).time)
                        .font(.caption2).strikethrough().foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            if let day = shown.day {
                Text(day).font(.caption2).foregroundStyle(.secondary)
            }
            if train.journeyClock.crossesTimeZones {
                Text(localization.journeyText(train.journeyClock.clock(atStopIndex: index).name))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let label = StopTimingStatus.localizedLabel(
                scheduled: planned, actual: actual, localization: localization) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            if let platform = stop.platformNumber, platform >= 0 {
                Text(localization.countryText("table.platform", fallback: "Platform") + " \(platform)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journeyStation-\(train.id)-\(index)")
    }

    private var stationTitle: Text {
        let translated = localization.stationName(stop.name, in: train, code: stop.n02StationCode)
        guard display?.showJourneyTranslations == true, translated != stop.name else {
            return Text(verbatim: stop.name)
        }
        return Text(verbatim: translated)
            + Text(verbatim: " (\(stop.name))").font(.caption2).fontWeight(.regular)
                .foregroundStyle(.secondary)
    }

    private func displayTime(_ raw: String?) -> (time: String, day: String?) {
        guard let raw else { return ("—", nil) }
        guard let date = train.date,
              case .valid(_, let clock) = EditorTime.parseTime(raw),
              clock.dayOffset > 0,
              let day = Dates.addDays(date, clock.dayOffset) else { return (raw, nil) }
        return (String(format: "%02d:%02d", clock.hour, clock.minute), day)
    }
}

/// Line names belong only to the expanded journey menu.
struct JourneyMenuRouteInformation: View {
    let train: Train
    @Environment(RailNetworkStore.self) private var network: RailNetworkStore?

    var body: some View {
        let route = JourneyBranding.routeText(
            of: train, detected: RideStatusCenter.shared.traversedLines(forTrainID: train.id),
            badges: network?.badges)
        if !route.isEmpty {
            Text(route)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("journeyMenuRoute-\(train.id)")
        }
    }
}
