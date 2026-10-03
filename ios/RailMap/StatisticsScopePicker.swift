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

    private var occupiedDates: Set<String> { Set(availableDates) }
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .gmt
        result.locale = localization.locale
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 0) {
                        classification(.date, text: localization.statisticsScopeText("byDate"))
                        classification(.journeyGroup, text: localization.statisticsScopeText("byGroup"))
                    }
                    if statistics.classification == .date {
                        dateCalendar
                    } else {
                        VStack(spacing: 0) {
                            groupChoice(nil, name: localization.groupText("all"))
                            ForEach(groups, id: \.id) { group in
                                groupChoice(group.id, name: group.name)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("statisticsJourneyGroupFilter")
                    }
                }
                .padding(16)
            }
            .navigationTitle(localization.statsText("ios.stats.scope"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.statisticsScopeText("done")) { dismiss() }
                }
            }
        }
        .frame(idealWidth: 390, maxWidth: 440, idealHeight: 610)
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
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localization.statisticsScopeText("previousMonth"))
                .accessibilityIdentifier("statisticsCalendarPrevious")
                Spacer(minLength: 0)
                monthMenu
                Spacer(minLength: 0)
                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localization.statisticsScopeText("nextMonth"))
                .accessibilityIdentifier("statisticsCalendarNext")
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let weekday = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(monthCells, id: \.self) { day in
                    if day > 0 {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 44).accessibilityHidden(true)
                    }
                }
            }
            .accessibilityIdentifier("statisticsCalendar")

            Text(localization.statisticsDateScopeLabel(statistics.dateSelection))
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("statisticsCalendarSelection")
            Text(localization.statisticsScopeText("instructions"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localization.countryText("date.all", fallback: "All dates")) {
                statistics.clearDates()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("statisticsCalendarClear")
        }
    }

    private var monthMenu: some View {
        Menu {
            Picker(localization.statisticsScopeText("year"), selection: Binding(
                get: { calendar.component(.year, from: displayedMonth) },
                set: { setMonth(year: $0, month: calendar.component(.month, from: displayedMonth)) })) {
                ForEach(calendarYears, id: \.self) { year in Text(String(year)).tag(year) }
            }
            Picker(localization.statisticsScopeText("month"), selection: Binding(
                get: { calendar.component(.month, from: displayedMonth) },
                set: { setMonth(year: calendar.component(.year, from: displayedMonth), month: $0) })) {
                ForEach(1...12, id: \.self) { month in
                    Text(calendar.monthSymbols[month - 1]).tag(month)
                }
            }
        } label: {
            Text(displayedMonth.formatted(Date.FormatStyle(
                locale: localization.locale, calendar: calendar, timeZone: .gmt).year().month(.wide)))
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(minHeight: 44)
        }
        .railMenuButtonStyle()
        .accessibilityIdentifier("statisticsCalendarMonth")
    }

    private var calendarYears: [Int] {
        var years = Set(availableDates.compactMap { Int($0.prefix(4)) })
        years.insert(calendar.component(.year, from: displayedMonth))
        years.insert(calendar.component(.year, from: Date()))
        return years.sorted()
    }

    private var monthCells: [Int] {
        let first = monthStart
        let padding = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: first) ?? 1..<29
        // Negative identities for leading spaces keep every cell stable and unique.
        return (0..<padding).map { -$0 } + Array(days)
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    }

    private func dayButton(_ day: Int) -> some View {
        let point = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let key = dateKey(point)
        let selection = statistics.dateSelection
        let selected = selection.contains(key)
        let occupied = occupiedDates.contains(key)
        let endpoint = selected && (selection.start == key || selection.end == key)
        return Button { statistics.tapDate(key, availableDates: occupiedDates) } label: {
            Text(String(day))
                .font(.body.monospacedDigit().weight(endpoint ? .bold : .regular))
                .foregroundStyle(endpoint ? Color.white : occupied ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        Rectangle().fill(Color.accentColor.opacity(0.16))
                        if endpoint { Circle().fill(Color.accentColor).padding(2) }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(endpoint ? Color.white : Color.accentColor)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selection.canSelect(key, availableDates: occupiedDates))
        .accessibilityLabel(Text(point.formatted(Date.FormatStyle(
            locale: localization.locale, calendar: calendar, timeZone: .gmt).year().month().day())))
        .accessibilityValue(occupied ? "" : localization.statisticsScopeText("noJourneys"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("statisticsCalendarDay-\(key)")
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? displayedMonth
    }

    private func setMonth(year: Int, month: Int) {
        displayedMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? displayedMonth
    }

    private func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func dateKey(_ point: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: point)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
