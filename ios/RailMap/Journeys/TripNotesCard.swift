import RailCore
import SwiftUI

// MARK: - what the form edits

/// A note while the form edits it. Held by ``TripNoteFlow`` rather than by the
/// form, so a map pick that closes the form for a moment does not lose it.
struct TripNoteDraft: Equatable {
    var id: String
    var isNew: Bool
    var category: String
    var text: String
    /// Service-day "HH:MM", or nil for "no time".
    var time: String?
    var anchor: TripNoteAnchor
}

/// Which trip-note surface is up, for one trip card. One instance per
/// presenter, so a tap on a row, on a map "!" and on "Add note" can never
/// present two sheets at once.
@MainActor @Observable
final class TripNoteFlow {
    enum Screen: Equatable, Identifiable {
        case read(noteID: String)
        case form

        var id: String {
            switch self {
            case .read(let noteID): "read-\(noteID)"
            case .form: "form"
            }
        }
    }

    var screen: Screen?
    var draft: TripNoteDraft?
    private(set) var original: TripNoteDraft?
    var saveRefused = false
    /// True from Save until persistence answers, so a second tap cannot race it.
    var isSaving = false

    /// Pick a place on the map: the anchor to start from (nil for a new
    /// note), and a callback that hears the confirmed anchor, or nil when the
    /// pick was cancelled. Nil here means the surface has no map, and the form
    /// offers the trip's stations instead.
    @ObservationIgnored var pickPlace: ((TripNoteAnchor?, @escaping (TripNoteAnchor?) -> Void) -> Void)?

    var isEdited: Bool { draft != original }

    /// "Add note": the place comes first, the form only after it.
    func beginAdd(train: Train, now: Date = Date()) {
        let open: (TripNoteAnchor) -> Void = { [weak self] anchor in
            self?.openForm(TripNoteDraft(
                id: UUID().uuidString.lowercased(), isNew: true, category: "", text: "",
                time: TripNoteTime.suggested(
                    for: train, stopIndex: Self.stopIndex(of: anchor, in: train), now: now,
                    clock: Region.resolved(train).clock),
                anchor: anchor))
        }
        if let pickPlace {
            pickPlace(nil) { anchor in
                if let anchor { open(anchor) }
            }
        } else if let first = train.stops.first {
            open(.station(TripNoteStation(stop: first), fallback: nil))
        }
    }

    func beginEdit(_ note: TripNote) {
        openForm(TripNoteDraft(
            id: note.id, isNew: false, category: note.category, text: note.text,
            time: note.time, anchor: note.anchor))
    }

    /// Change place from the form: close it, pick, and bring it back with
    /// every unsaved edit and either the new place or the old one.
    func changePlaceOnMap() {
        guard let pickPlace, let current = draft?.anchor else { return }
        screen = nil
        // A place this build cannot read has nothing to start the pick from.
        var initial: TripNoteAnchor? = current
        if case .unknown = current { initial = nil }
        pickPlace(initial) { [weak self] picked in
            guard let self, self.draft != nil else { return }
            if let picked { self.draft?.anchor = picked }
            self.screen = .form
        }
    }

    /// The owner is going away: drop whatever is open or half-edited.
    func reset() {
        screen = nil
        draft = nil
        original = nil
        isSaving = false
    }

    private func openForm(_ draft: TripNoteDraft) {
        self.draft = draft
        original = draft
        screen = .form
    }

    private static func stopIndex(of anchor: TripNoteAnchor, in train: Train) -> Int? {
        switch TripNotePlacement.resolve(anchor, stops: train.stops) {
        case .station(let index): index
        case .interval(let from, _, _): from
        default: nil
        }
    }
}

// MARK: - text helpers

/// The words a note's place and time are shown in, shared by the row, the
/// read card and the form.
@MainActor
struct TripNoteDescriber {
    let train: Train
    let localization: AppLocalization

    private var region: Region { Region.resolved(train) }
    var clock: RegionClock { region.clock }

    func place(_ anchor: TripNoteAnchor) -> String {
        switch TripNotePlacement.resolve(anchor, stops: train.stops) {
        case .station(let index):
            return localization.text("ios.tripNotes.placeAtStation",
                                     params: ["station": .string(stationName(index))])
        case .interval(let from, let to, _):
            return localization.text("ios.tripNotes.placeBetween", params: [
                "from": .string(stationName(from)), "to": .string(stationName(to)),
            ])
        case .coordinate: return localization.text("ios.tripNotes.placeOnMap")
        case .unplaced: return localization.text("ios.tripNotes.placeUnplaced")
        }
    }

    func stationName(_ index: Int) -> String {
        let stop = train.stops[index]
        return localization.stationName(stop.name, code: stop.n02StationCode, region: region)
    }

    /// "01:10 (+1) UTC+9", or nil without a time.
    func time(_ time: String?) -> String? {
        guard let shown = TripNoteTime.display(time) else { return nil }
        var text = shown.clock
        if shown.dayOffset > 0 {
            text += " (" + localization.text("ios.tripNotes.nextDay",
                                             params: ["n": .number(Double(shown.dayOffset))]) + ")"
        }
        return text + " " + clock.utcOffsetText(at: Date())
    }

    /// "Notes 1 · 2026-10-12": the trip as its card header names it.
    var tripTitle: String {
        [train.number, train.date ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The one plain string a share carries; the body is exactly as stored.
    func shareText(_ note: TripNote) -> String {
        TripNoteShareText.compose(
            category: note.category, time: time(note.time), place: place(note.anchor),
            trip: tripTitle, body: note.text)
    }

    func starters() -> [String] {
        ["incident", "observation", "finding", "unscheduledStop", "crewChange", "other"]
            .map { localization.text("ios.tripNotes.category.default.\($0)") }
    }
}

// MARK: - the list card

/// The notes already on a trip, and an add row. Absent when there are none:
/// the trip card's primary "Add note" button is the way in.
struct TripNotesCard: View {
    let train: Train
    let flow: TripNoteFlow
    var surface: AnyShapeStyle = AnyShapeStyle(.background)

    @Environment(AppLocalization.self) private var localization
    @ScaledMetric(relativeTo: .body) private var discSide: CGFloat = 28

    private var notes: [TripNote] { train.tripNotes ?? [] }

    private var describer: TripNoteDescriber {
        TripNoteDescriber(train: train, localization: localization)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RailSpacing.s12) {
            Text(localization.text("ios.tripNotes.title")).font(.headline)
            ForEach(notes) { note in row(note) }
            Button {
                flow.beginAdd(train: train)
            } label: {
                Label(localization.text("ios.tripNotes.add"), systemImage: "plus")
            }
            .buttonStyle(RailCapsuleButtonStyle())
            .railMinimumTouchTarget()
            .accessibilityIdentifier("tripNotesListAdd")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RailSpacing.s16)
        .background(
            surface,
            in: RoundedRectangle(cornerRadius: RailStyle.cardCornerRadius, style: .continuous))
        // `.contain`: without it the card's id replaces its children's ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripNotesCard")
    }

    private func row(_ note: TripNote) -> some View {
        let describer = describer
        return Button {
            flow.screen = .read(noteID: note.id)
        } label: {
            HStack(alignment: .top, spacing: RailSpacing.s12) {
                Text("!")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: discSide, height: discSide)
                    .background(Color(red: 1.0, green: 0.72, blue: 0.1), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if !note.category.isEmpty {
                        Text(note.category).font(.subheadline.weight(.semibold))
                    }
                    if let time = describer.time(note.time) {
                        Text(time).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(describer.place(note.anchor)).font(.footnote).foregroundStyle(.secondary)
                    if !note.text.isEmpty {
                        Text(note.text).font(.footnote).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: RailStyle.minimumTouchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tripNoteRow")
    }
}

// MARK: - the sheets

extension View {
    /// Presents the read card and the form for `flow`. `onSet` writes the
    /// trip's whole note list and says whether the save went through.
    func tripNotesPresentation(
        flow: TripNoteFlow, train: Train, trains: [Train],
        onSet: (([TripNote]) async -> Bool)?
    ) -> some View {
        modifier(TripNotesPresentation(flow: flow, train: train, trains: trains, onSet: onSet))
    }
}

private struct TripNotesPresentation: ViewModifier {
    @Bindable var flow: TripNoteFlow
    let train: Train
    let trains: [Train]
    let onSet: (([TripNote]) async -> Bool)?
    @Environment(AppLocalization.self) private var localization

    func body(content: Content) -> some View {
        content.sheet(item: $flow.screen) { screen in
            Group {
                switch screen {
                case .read(let noteID):
                    TripNoteReadCard(flow: flow, train: train, noteID: noteID, onSet: onSet)
                case .form:
                    TripNoteFormSheet(flow: flow, train: train, trains: trains, onSet: onSet)
                }
            }
            .environment(localization)
        }
    }
}

private struct TripNoteReadCard: View {
    @Bindable var flow: TripNoteFlow
    let train: Train
    let noteID: String
    let onSet: (([TripNote]) async -> Bool)?
    @Environment(AppLocalization.self) private var localization
    @State private var confirmsDelete = false

    private var note: TripNote? { train.tripNotes?.first { $0.id == noteID } }

    var body: some View {
        NavigationStack {
            Group {
                if let note {
                    let describer = TripNoteDescriber(train: train, localization: localization)
                    ScrollView {
                        VStack(alignment: .leading, spacing: RailSpacing.s12) {
                            if !note.category.isEmpty {
                                Text(note.category).font(.title3.weight(.semibold))
                            }
                            if !note.text.isEmpty {
                                Text(note.text).font(.body).textSelection(.enabled)
                            }
                            LabeledContent(localization.text("ios.tripNotes.time"),
                                           value: describer.time(note.time)
                                           ?? localization.text("ios.tripNotes.noTime"))
                            LabeledContent(localization.text("ios.tripNotes.place"),
                                           value: describer.place(note.anchor))
                            HStack(spacing: RailSpacing.s12) {
                                Button(localization.text("ios.tripNotes.edit"), systemImage: "pencil") {
                                    flow.beginEdit(note)
                                }
                                .buttonStyle(RailCapsuleButtonStyle())
                                .railMinimumTouchTarget()
                                .accessibilityIdentifier("tripNoteEdit")
                                ShareLink(item: describer.shareText(note)) {
                                    Label(localization.text("ios.tripNotes.share"),
                                          systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(RailCapsuleButtonStyle())
                                .railMinimumTouchTarget()
                                .accessibilityIdentifier("tripNoteShare")
                                Button(localization.text("ios.tripNotes.delete"), systemImage: "trash",
                                       role: .destructive) { confirmsDelete = true }
                                    .buttonStyle(RailCapsuleButtonStyle())
                                    .railMinimumTouchTarget()
                                    .accessibilityIdentifier("tripNoteDelete")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RailSpacing.s16)
                    }
                    .confirmationDialog(
                        localization.text("ios.tripNotes.deleteConfirm"),
                        isPresented: $confirmsDelete, titleVisibility: .visible
                    ) {
                        Button(localization.text("ios.tripNotes.delete"), role: .destructive) {
                            delete(note)
                        }
                        .accessibilityIdentifier("tripNoteDeleteConfirm")
                        Button(localization.text("ios.tripNotes.cancel"), role: .cancel) {}
                    }
                } else {
                    Color.clear.onAppear { flow.screen = nil }
                }
            }
            .navigationTitle(localization.text("ios.tripNotes.title"))
            .navigationBarTitleDisplayMode(.inline)
            .railSheetClose(
                Text(localization.text("ios.close", fallback: "Close")),
                identifier: "tripNotesClose"
            ) { flow.screen = nil }
            .alert(localization.text("ios.tripNotes.saveRefused"), isPresented: $flow.saveRefused) {
                Button(localization.text("ios.done", fallback: "Done"), role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("tripNoteReadCard")
    }

    private func delete(_ note: TripNote) {
        let remaining = (train.tripNotes ?? []).filter { $0.id != note.id }
        guard !flow.isSaving else { return }
        flow.isSaving = true
        Task { @MainActor in
            let saved = await onSet?(remaining) == true
            flow.isSaving = false
            if saved { flow.screen = nil } else { flow.saveRefused = true }
        }
    }
}

private struct TripNoteFormSheet: View {
    @Bindable var flow: TripNoteFlow
    let train: Train
    let trains: [Train]
    let onSet: (([TripNote]) async -> Bool)?
    @Environment(AppLocalization.self) private var localization
    @State private var confirmsDiscard = false

    private var describer: TripNoteDescriber {
        TripNoteDescriber(train: train, localization: localization)
    }

    private var draft: Binding<TripNoteDraft> {
        Binding(get: { flow.draft ?? Self.empty }, set: { flow.draft = $0 })
    }

    private static let empty = TripNoteDraft(
        id: "", isNew: true, category: "", text: "", time: nil,
        anchor: .coordinate(Coordinate(lon: 0, lat: 0)))

    private var canSave: Bool {
        let value = draft.wrappedValue
        return !(value.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                Section {
                    TextEditor(text: draft.text)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if draft.wrappedValue.text.isEmpty {
                                Text(localization.text("ios.tripNotes.textPlaceholder"))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, RailSpacing.s8).padding(.leading, RailSpacing.s4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(localization.text("ios.tripNotes.text"))
                        .accessibilityIdentifier("tripNoteText")
                } header: {
                    Text(localization.text("ios.tripNotes.text"))
                }
                timeSection
                placeSection
            }
            .navigationTitle(localization.text(draft.wrappedValue.isNew
                                               ? "ios.tripNotes.add" : "ios.tripNotes.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.tripNotes.cancel")) {
                        if flow.isEdited { confirmsDiscard = true } else { flow.screen = nil }
                    }
                    .accessibilityIdentifier("tripNoteCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.text("ios.tripNotes.save")) { save() }
                        .disabled(!canSave || flow.isSaving)
                        .accessibilityIdentifier("tripNoteSave")
                }
            }
            .confirmationDialog(
                localization.text("ios.tripNotes.discardConfirm"),
                isPresented: $confirmsDiscard, titleVisibility: .visible
            ) {
                Button(localization.text("ios.tripNotes.discard"), role: .destructive) {
                    flow.screen = nil
                }
                Button(localization.text("ios.tripNotes.cancel"), role: .cancel) {}
            }
            .alert(localization.text("ios.tripNotes.saveRefused"), isPresented: $flow.saveRefused) {
                Button(localization.text("ios.done", fallback: "Done"), role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(flow.isEdited || flow.isSaving)
        .presentationDetents([.large])
        .accessibilityIdentifier("tripNoteForm")
    }

    // MARK: category

    private var categorySection: some View {
        Section {
            TextField(localization.text("ios.tripNotes.categoryPlaceholder"),
                      text: draft.category)
                .accessibilityLabel(localization.text("ios.tripNotes.category"))
                .accessibilityIdentifier("tripNoteCategory")
            let chips = TripNoteEditing.filteredSuggestions(suggestions, typed: draft.wrappedValue.category)
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RailSpacing.s8) {
                        ForEach(chips, id: \.self) { chip in
                            Button { flow.draft?.category = chip } label: { chipLabel(chip) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("tripNoteCategorySuggestion")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        } header: {
            Text(localization.text("ios.tripNotes.category"))
        }
    }

    private var suggestions: [String] {
        TripNoteCategories.suggestions(from: trains, starters: describer.starters())
    }

    /// Same capsule as the station picker's filter chip, which is private there.
    private func chipLabel(_ title: String) -> some View {
        Text(title).lineLimit(1)
            .font(.subheadline)
            .padding(.horizontal, RailSpacing.s12)
            .padding(.vertical, RailSpacing.s8)
            .foregroundStyle(Color.primary)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .frame(minHeight: RailStyle.minimumTouchTarget)
            .contentShape(.rect)
    }

    // MARK: time

    private var timeSection: some View {
        let clock = describer.clock
        let hasTime = Binding(
            get: { draft.wrappedValue.time != nil },
            set: { on in
                flow.draft?.time = on
                    ? (TripNoteTime.suggested(for: train, stopIndex: nil, now: Date(),
                                              clock: clock) ?? "00:00")
                    : nil
            })
        let picked = Binding<Date>(
            get: {
                TripNoteEditing.pickerInstant(
                    serviceDate: train.date, time: draft.wrappedValue.time, clock: clock,
                    reference: Date())
            },
            set: { instant in
                if let time = TripNoteEditing.time(
                    forPicked: instant, serviceDate: train.date, clock: clock,
                    carryingDayOf: draft.wrappedValue.time) {
                    flow.draft?.time = time
                }
            })
        return Section {
            Toggle(localization.text("ios.tripNotes.noTime"), isOn: Binding(
                get: { !hasTime.wrappedValue }, set: { hasTime.wrappedValue = !$0 }))
                .accessibilityIdentifier("tripNoteNoTime")
            if draft.wrappedValue.time != nil {
                Group {
                    if let range = TripNoteEditing.pickerRange(serviceDate: train.date, clock: clock) {
                        DatePicker(localization.text("ios.tripNotes.time"), selection: picked,
                                   in: range, displayedComponents: [.date, .hourAndMinute])
                            .environment(\.timeZone, clock.timeZone)
                    } else {
                        DatePicker(localization.text("ios.tripNotes.time"), selection: picked,
                                   displayedComponents: [.hourAndMinute])
                            .environment(\.timeZone, clock.timeZone)
                    }
                }
                .environment(\.calendar, clock.calendar)
                .accessibilityIdentifier("tripNoteTime")
                if let label = describer.time(draft.wrappedValue.time) {
                    Text(label).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(localization.text("ios.tripNotes.time"))
        }
    }

    // MARK: place

    private var placeSection: some View {
        Section {
            HStack {
                Text(describer.place(draft.wrappedValue.anchor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tripNotePlace")
                if flow.pickPlace != nil {
                    Button(localization.text("ios.tripNotes.changePlace")) { flow.changePlaceOnMap() }
                        .accessibilityIdentifier("tripNoteChangePlace")
                } else {
                    Menu(localization.text("ios.tripNotes.changePlace")) {
                        ForEach(train.stops.indices, id: \.self) { index in
                            Button(describer.stationName(index)) {
                                flow.draft?.anchor = .station(
                                    TripNoteStation(stop: train.stops[index]), fallback: nil)
                            }
                        }
                    }
                    .accessibilityIdentifier("tripNoteChangePlace")
                }
            }
            .frame(minHeight: RailStyle.minimumTouchTarget)
        } header: {
            Text(localization.text("ios.tripNotes.place"))
        }
    }

    // MARK: save

    private func save() {
        guard let value = flow.draft else { return }
        let existing = TripNoteCategories.suggestions(
            from: trains, starters: describer.starters(), limit: .max)
        let category = TripNoteEditing.canonicalCategory(value.category, existing: existing)
        let note = TripNote(id: value.id, category: category, text: value.text,
                            time: value.time, anchor: value.anchor)
        var notes = train.tripNotes ?? []
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        // The draft stays in the flow until persistence confirms, so a failed
        // save leaves the form open for another try.
        guard !flow.isSaving else { return }
        flow.isSaving = true
        Task { @MainActor in
            let saved = await onSet?(notes) == true
            flow.isSaving = false
            if saved { flow.screen = nil } else { flow.saveRefused = true }
        }
    }
}
