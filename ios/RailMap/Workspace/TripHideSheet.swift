import RailCore
import SwiftUI

/// Choose which whole regions, years or months — opened from the scope filter on
/// every tab and from the map's "Showing 500 of N" notice.
struct TripHideSheet: View {
    @Bindable var filter: TripHideFilter
    let trains: [Train]
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let regions = filter.regions(trains)
        let calendar = filter.calendar(trains)
        NavigationStack {
            Form {
                if regions.count > 1 {
                    Section {
                        ForEach(regions) { region in
                            Toggle(localization.text(region.localizationKey, fallback: region.fallbackName),
                                   isOn: Binding(
                                    get: { !filter.isRegionHidden(region) },
                                    set: { filter.setRegion(region, hidden: !$0) }))
                            .accessibilityIdentifier("tripHideRegion-\(region.code)")
                        }
                    } header: {
                        Text(localization.text("ios.hide.regions", fallback: "Show trips from"))
                    }
                }
                ForEach(calendar, id: \.year) { entry in
                    Section {
                        Toggle(String(entry.year), isOn: Binding(
                            get: { !filter.isYearHidden(entry.year) },
                            set: { filter.setYear(entry.year, hidden: !$0) }))
                        .font(.headline)
                        .accessibilityIdentifier("tripHideYear-\(entry.year)")
                        DisclosureGroup(localization.text("ios.hide.months", fallback: "Months")) {
                            ForEach(entry.months, id: \.self) { month in
                                Toggle(monthLabel(month), isOn: Binding(
                                    get: { !filter.isMonthHidden(month) },
                                    set: { filter.setMonth(month, hidden: !$0) }))
                                .accessibilityIdentifier("tripHideMonth-\(month)")
                            }
                        }
                    }
                }
                Section {
                    Button(localization.text("ios.hide.showAll", fallback: "Show all")) {
                        filter.showAll()
                    }
                    .disabled(!filter.isActive)
                    .accessibilityIdentifier("tripHideShowAll")
                } footer: {
                    Text(localization.text(
                        "ios.hide.note",
                        fallback: "Hidden regions and months leave the map, the lists and Stats. A single trip's own Hide only takes that trip off the map."))
                }
            }
            .navigationTitle(localization.text("ios.hide.title", fallback: "Regions and months shown"))
            .navigationBarTitleDisplayMode(.inline)
            .railSheetClose(
                Text(localization.text("ios.close", fallback: "Close")),
                identifier: "tripHideDone"
            ) { dismiss() }
        }
        .railSheet(.halfNonModal)
        .accessibilityIdentifier("tripHideSheet")
    }

    private func monthLabel(_ month: String) -> String {
        guard let number = Int(month.suffix(2)) else { return month }
        return StatisticsFormat.monthName(number, localization: localization)
    }
}
