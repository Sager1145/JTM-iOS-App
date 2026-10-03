import Foundation
import RailCore
import RailPresentation
import SwiftUI

/// One mutually exclusive classification, owned by the statistics store.
struct StatisticsScopePicker: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Bindable var statistics: MileageStatisticsStore
    let availableDates: [String]
    let groups: [JourneyGroup]
    var selectGroup: (String?) -> Void

    @State private var displayedMonth = Date()
    /// Which way the last month change went, so the grid slides the matching way.
    @State private var monthStep = 1

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .gmt
        result.locale = localization.locale
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        classification(.date, text: localization.statisticsScopeText("byDate"))
                        Divider()
                        classification(.journeyGroup, text: localization.statisticsScopeText("byGroup"))
                    }
                    .padding(.horizontal, 16)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if statistics.classification == .date {
                        dateCalendar
                    } else {
                        VStack(spacing: 0) {
                            groupChoice(nil, name: localization.groupText("all"))
                            ForEach(groups, id: \.id) { group in
                                Divider()
                                groupChoice(group.id, name: group.name)
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("statisticsJourneyGroupFilter")
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localization.statsText("ios.stats.scope"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.statisticsScopeText("done")) { dismiss() }
                }
            }
        }
        .frame(idealWidth: 390, maxWidth: 440, idealHeight: 640)
        .task {
            displayedMonth = date(statistics.dateSelection.start ?? availableDates.last ?? "") ?? Date()
        }
        .onChange(of: availableDates) { previous, dates in
            // A sheet can open before the library has finished loading.
            if previous.isEmpty, let latest = dates.last {
                displayedMonth = date(statistics.dateSelection.start ?? latest) ?? displayedMonth
            }
        }
        .accessibilityIdentifier("statisticsScopePicker")
    }

    private func classification(_ mode: MileageStatisticsStore.Classification, text: String) -> some View {
        Button { statistics.selectClassification(mode) } label: {
            HStack {
                Text(text).foregroundStyle(.primary)
                Spacer()
                Image(systemName: statistics.classification == mode ? "checkmark.circle.fill" : "circle")
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(statistics.classification == mode ? .isSelected : [])
        .accessibilityIdentifier("statisticsClassification-\(mode.rawValue)")
    }

    private func groupChoice(_ id: String?, name: String) -> some View {
        Button { selectGroup(id) } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                Image(systemName: statistics.selectedJourneyGroupID == id ? "checkmark.circle.fill" : "circle")
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(statistics.selectedJourneyGroupID == id ? .isSelected : [])
        .accessibilityIdentifier("statisticsGroup-\(id ?? "all")")
    }

    private var dateCalendar: some View {
        // Built once per body: every cell used to rebuild the occupied set,
        // a Calendar and a FormatStyle for itself.
        let month = CalendarMonth(
            containing: displayedMonth, calendar: calendar,
            selection: statistics.dateSelection, occupied: Set(availableDates))
        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                HStack {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localization.statisticsScopeText("previousMonth"))
                    .accessibilityIdentifier("statisticsCalendarPrevious")
                    Spacer(minLength: 0)
                    monthMenu
                    Spacer(minLength: 0)
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localization.statisticsScopeText("nextMonth"))
                    .accessibilityIdentifier("statisticsCalendarNext")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(month.weekdaySymbols.indices, id: \.self) { index in
                            Text(month.weekdaySymbols[index])
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                    // A ZStack so the outgoing and incoming months overlap while sliding.
                    ZStack {
                        weeks(month, noJourneys: localization.statisticsScopeText("noJourneys"))
                            .id(month.id)
                            .transition(.push(from: monthStep > 0 ? .trailing : .leading))
                    }
                    .clipped()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("statisticsCalendar")
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .sensoryFeedback(.selection, trigger: statistics.dateSelection)

            HStack(alignment: .firstTextBaseline) {
                Text(localization.statisticsDateScopeLabel(statistics.dateSelection))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("statisticsCalendarSelection")
                Button(localization.countryText("date.all", fallback: "All dates")) {
                    statistics.clearDates()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("statisticsCalendarClear")
            }
            .padding(.horizontal, 4)
            Text(localization.statisticsScopeText("instructions"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    /// Always six rows, so the sheet keeps one height from month to month.
    private func weeks(_ month: CalendarMonth, noJourneys: String) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 4) {
            ForEach(month.weeks.indices, id: \.self) { row in
                GridRow {
                    ForEach(month.weeks[row].indices, id: \.self) { column in
                        if let day = month.weeks[row][column] {
                            CalendarDayCell(day: day, noJourneys: noJourneys, revision: month.occupiedRevision) {
                                statistics.tapDate(day.key, availableDates: month.occupied)
                            }
                            .equatable()
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: CalendarDayCell.height)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private var monthMenu: some View {
        let calendar = calendar
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)
        return Menu {
            Picker(localization.statisticsScopeText("year"), selection: Binding(
                get: { year }, set: { setMonth(year: $0, month: month) })) {
                ForEach(calendarYears, id: \.self) { year in Text(String(year)).tag(year) }
            }
            Picker(localization.statisticsScopeText("month"), selection: Binding(
                get: { month }, set: { setMonth(year: year, month: $0) })) {
                ForEach(1...12, id: \.self) { month in
                    Text(calendar.monthSymbols[month - 1]).tag(month)
                }
            }
        } label: {
            Text(displayedMonth.formatted(Date.FormatStyle(
                locale: localization.locale, calendar: calendar, timeZone: .gmt).year().month(.wide)))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
        }
        .railMenuButtonStyle()
        .accessibilityIdentifier("statisticsCalendarMonth")
    }

    private var calendarYears: [Int] {
        let calendar = calendar
        var years = Set(availableDates.compactMap { Int($0.prefix(4)) })
        years.insert(calendar.component(.year, from: displayedMonth))
        years.insert(calendar.component(.year, from: Date()))
        return years.sorted()
    }

    private func moveMonth(_ offset: Int) {
        let calendar = calendar
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
            ?? displayedMonth
        changeMonth(to: calendar.date(byAdding: .month, value: offset, to: start))
    }

    private func setMonth(year: Int, month: Int) {
        changeMonth(to: calendar.date(from: DateComponents(year: year, month: month, day: 1)))
    }

    private func changeMonth(to target: Date?) {
        guard let target, target != displayedMonth else { return }
        let step = target > displayedMonth ? 1 : -1
        guard step != monthStep else {
            withAnimation(.snappy(duration: 0.28)) { displayedMonth = target }
            return
        }
        // The outgoing grid leaves with the transition it was last rendered with,
        // so a reversal must re-render it with the new direction before it slides.
        monthStep = step
        Task { @MainActor in
            withAnimation(.snappy(duration: 0.28)) { displayedMonth = target }
        }
    }

    private func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// One displayed month, with every cell's state resolved up front so the
/// cells themselves are plain values SwiftUI can diff and skip.
private struct CalendarMonth {
    struct Day: Equatable {
        let key: String
        let number: Int
        let label: String
        let isOccupied: Bool
        let isSelected: Bool
        let isEndpoint: Bool
        let isEnabled: Bool
        let isToday: Bool
        /// The selection band runs on into the neighbouring cell of the same week.
        var joinsLeading = false
        var joinsTrailing = false
    }

    let id: String
    let occupied: Set<String>
    /// Changes whenever `occupied` does, so equatable cells drop tap handlers holding an old set.
    let occupiedRevision: Int
    let weekdaySymbols: [String]
    let weeks: [[Day?]]

    init(containing point: Date, calendar: Calendar,
         selection: StatisticsDateSelection, occupied: Set<String>) {
        let parts = calendar.dateComponents([.year, .month], from: point)
        let year = parts.year ?? 1970, monthNumber = parts.month ?? 1
        let start = calendar.date(from: DateComponents(year: year, month: monthNumber, day: 1)) ?? point
        let padding = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: .gmt)
            .year().month().day()
        // "Today" is the reader's local day, not the GMT day the keys are in.
        // Gregorian by name: a device on the Japanese calendar would answer year 8.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let now = local.dateComponents([.year, .month, .day], from: Date())
        let today = String(format: "%04d-%02d-%02d", now.year ?? 0, now.month ?? 0, now.day ?? 0)

        var cells: [Day?] = Array(repeating: nil, count: padding)
        for number in 1...count {
            let key = String(format: "%04d-%02d-%02d", year, monthNumber, number)
            let selected = selection.contains(key)
            let label = (calendar.date(byAdding: .day, value: number - 1, to: start) ?? start)
                .formatted(style)
            cells.append(Day(
                key: key, number: number, label: label,
                isOccupied: occupied.contains(key), isSelected: selected,
                isEndpoint: selected && (selection.start == key || selection.end == key),
                isEnabled: selection.canSelect(key, availableDates: occupied),
                isToday: key == today))
        }
        cells += Array(repeating: nil, count: 42 - cells.count)

        var weeks = stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
        for row in weeks.indices {
            let selected = weeks[row].map { $0?.isSelected == true }
            for column in 0..<7 where selected[column] {
                weeks[row][column]?.joinsLeading = column > 0 && selected[column - 1]
                weeks[row][column]?.joinsTrailing = column < 6 && selected[column + 1]
            }
        }

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        self.id = String(format: "%04d-%02d", year, monthNumber)
        self.occupied = occupied
        self.occupiedRevision = occupied.hashValue
        self.weekdaySymbols = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        self.weeks = weeks
    }
}

/// A day as a value view: a tap re-renders only the cells whose state changed.
private struct CalendarDayCell: View, Equatable {
    static let height: CGFloat = 44
    private static let mark: CGFloat = 40

    let day: CalendarMonth.Day
    let noJourneys: String
    let revision: Int
    let action: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.noJourneys == rhs.noJourneys && lhs.revision == rhs.revision
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(String(day.number))
                    .font(.body.monospacedDigit().weight(
                        day.isEndpoint || day.isToday ? .semibold : .regular))
                    .foregroundStyle(numberStyle)
                Circle()
                    .fill(day.isEndpoint ? AnyShapeStyle(.white) : AnyShapeStyle(Color.accentColor))
                    .frame(width: 4, height: 4)
                    .opacity(day.isOccupied ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background { band }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!day.isEnabled)
        .accessibilityLabel(Text(day.label))
        .accessibilityValue(day.isOccupied ? "" : noJourneys)
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
        .accessibilityIdentifier("statisticsCalendarDay-\(day.key)")
    }

    private var numberStyle: AnyShapeStyle {
        if day.isEndpoint { return AnyShapeStyle(.white) }
        if day.isToday { return AnyShapeStyle(Color.accentColor) }
        if day.isOccupied { return AnyShapeStyle(.primary) }
        return day.isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    /// A continuous pill across selected neighbours, rounded wherever the run breaks.
    @ViewBuilder private var band: some View {
        if day.isSelected {
            ZStack {
                // Composited before fading, so the halves and the disc never stack darker.
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle().fill(day.joinsLeading ? Color.accentColor : .clear)
                        Rectangle().fill(day.joinsTrailing ? Color.accentColor : .clear)
                    }
                    .frame(height: Self.mark)
                    Circle().frame(width: Self.mark, height: Self.mark)
                }
                .foregroundStyle(Color.accentColor)
                .compositingGroup()
                .opacity(0.18)
                if day.isEndpoint {
                    Circle().fill(Color.accentColor).frame(width: Self.mark, height: Self.mark)
                }
            }
        } else if day.isToday {
            Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                .frame(width: Self.mark, height: Self.mark)
        }
    }
}

extension AppLocalization {
    func statisticsDateScopeLabel(_ selection: StatisticsDateSelection) -> String {
        guard let start = selection.start, let end = selection.end else {
            return countryText("date.all", fallback: "All dates")
        }
        let label = start == end ? start : "\(start) – \(end)"
        guard !selection.excludedDates.isEmpty else { return label }
        return "\(label) · \(selection.excludedDates.count) \(statisticsScopeText("excluded"))"
    }

    func statisticsScopeText(_ key: String) -> String {
        let strings: [String: [Localization.Language: String]] = [
            "byDate": [.zhHans: "按照日期分类", .zhHant: "按照日期分類", .ja: "日付別", .en: "By date"],
            "byGroup": [.zhHans: "按照行程组分类", .zhHant: "按照行程組分類", .ja: "旅程グループ別", .en: "By journey group"],
            "done": [.zhHans: "完成", .zhHant: "完成", .ja: "完了", .en: "Done"],
            "year": [.zhHans: "年份", .zhHant: "年份", .ja: "年", .en: "Year"],
            "month": [.zhHans: "月份", .zhHant: "月份", .ja: "月", .en: "Month"],
            "previousMonth": [.zhHans: "上个月", .zhHant: "上個月", .ja: "前の月", .en: "Previous month"],
            "nextMonth": [.zhHans: "下个月", .zhHant: "下個月", .ja: "次の月", .en: "Next month"],
            "excluded": [.zhHans: "天已取消选择", .zhHant: "天已取消選取", .ja: "日を除外", .en: "days excluded"],
            "noJourneys": [.zhHans: "没有行程", .zhHant: "沒有行程", .ja: "旅程なし", .en: "No journeys"],
            "instructions": [
                .zhHans: "点击日期选择起点，再点击另一日期选择范围。再次点击已选日期可取消选择。灰色日期只能包含在范围内。",
                .zhHant: "點選日期選擇起點，再點選另一日期選擇範圍。再次點選已選日期可取消選取。灰色日期只能包含在範圍內。",
                .ja: "日付をタップして開始日を選び、別の日付で範囲を選択。選択済みの日付を再度タップすると除外できます。グレーの日付は範囲内のみ選択できます。",
                .en: "Tap a date to start, then another to select a range. Tap a selected date again to deselect it. Gray dates can only be included inside a range."
            ],
        ]
        return strings[key]?[language] ?? strings[key]?[.en] ?? key
    }
}
