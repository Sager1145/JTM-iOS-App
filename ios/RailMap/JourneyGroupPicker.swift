import RailCore
import SwiftUI

enum JourneyGroupCatalog {
    static func groups(in trains: [Train]) -> [JourneyGroup] {
        var seen = Set<String>()
        return trains.compactMap(\.journeyGroup)
            .filter { !$0.name.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Group creation belongs to the draft: cancelling leaves the library intact.
struct JourneyGroupChoiceFields: View {
    @Binding var selection: JourneyGroup?
    let groups: [JourneyGroup]
    @Environment(AppLocalization.self) private var localization
    @State private var newGroupID: String?
    @State private var name = ""

    var body: some View {
        Picker(localization.groupText("title"), selection: selectedID) {
            Text(localization.groupText("none")).tag(String?.none)
            ForEach(choices) { group in
                Text(group.name.isEmpty ? localization.groupText("name") : group.name).tag(Optional(group.id))
            }
        }
        .accessibilityIdentifier("journeyGroupPicker")
        .onAppear {
            if let selection, !groups.contains(where: { $0.id == selection.id }) {
                newGroupID = selection.id
                name = selection.name
            }
        }

        Button {
            let group = JourneyGroup(name: "")
            newGroupID = group.id
            name = ""
            selection = group
        } label: {
            Label(localization.groupText("create"), systemImage: "folder.badge.plus")
        }
        .accessibilityIdentifier("createJourneyGroup")

        if let newGroupID {
            TextField(localization.groupText("name"), text: $name)
                .submitLabel(.done)
                .accessibilityIdentifier("journeyGroupName")
                .onChange(of: name) { _, value in
                    let limited = String(value.filter { !$0.isNewline }.prefix(JourneyGroup.maxNameLength))
                    if name != limited { name = limited }
                    selection = JourneyGroup(id: newGroupID, name: limited)
                }
            Text("\(name.count)/\(JourneyGroup.maxNameLength) · \(localization.groupText("limit"))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("journeyGroupNameLimit")
        }
    }

    private var choices: [JourneyGroup] {
        guard let selection, !groups.contains(where: { $0.id == selection.id }) else { return groups }
        return groups + [selection]
    }

    private var selectedID: Binding<String?> {
        Binding(get: { selection?.id }, set: { id in
            selection = choices.first { $0.id == id }
            if let selection, !groups.contains(where: { $0.id == selection.id }) {
                newGroupID = selection.id
                name = selection.name
            } else {
                newGroupID = nil
            }
        })
    }
}

struct JourneyGroupAssignmentView: View {
    let train: Train
    let groups: [JourneyGroup]
    let editing: JourneyEditing
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @State private var selection: JourneyGroup?
    @State private var saving = false
    @State private var failed = false

    init(train: Train, groups: [JourneyGroup], editing: JourneyEditing) {
        self.train = train
        self.groups = groups
        self.editing = editing
        _selection = State(initialValue: train.journeyGroup)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    JourneyGroupChoiceFields(selection: $selection, groups: groups)
                } footer: {
                    Text(localization.groupText("crossRegion"))
                }
                if failed {
                    Text(localization.journeyText("ios.journey.saveFailedTitle", fallback: "Could not save this journey"))
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(localization.groupText("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.cancel", fallback: "Cancel")) { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.text("btn.save", fallback: "Save")) { save() }
                        .disabled(saving || selection?.name.isEmpty == true)
                        .accessibilityIdentifier("saveJourneyGroup")
                }
            }
            .disabled(saving)
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() {
        guard var current = editing.itineraries.store?.trains.first(where: { $0.id == train.id }) else {
            failed = true
            return
        }
        current.journeyGroup = selection
        let result = editing.replaceAndPersist(current, replacing: train.id)
        guard let persistence = result.persistence else { failed = true; return }
        saving = true
        Task { @MainActor in
            if await persistence.value {
                dismiss()
            } else {
                _ = result.rollback?()
                failed = true
            }
            saving = false
        }
    }
}
