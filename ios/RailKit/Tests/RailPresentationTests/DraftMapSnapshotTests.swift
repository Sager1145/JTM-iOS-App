import Foundation
import RailPresentation
import Testing

struct DraftMapSnapshotTests {
    private func pin(
        _ id: UUID,
        name: String = "Tokyo",
        timeText: String = "09:00",
        dayOffset: Int = 0,
        latitude: Double? = 35.6812,
        longitude: Double? = 139.7671
    ) -> DraftStopPin {
        DraftStopPin(
            occurrenceID: id,
            name: name,
            stopType: "stop",
            timeText: timeText,
            dayOffset: dayOffset,
            latitude: latitude,
            longitude: longitude)
    }

    @Test("Two visits at the same coordinates stay two pins")
    func sameCoordinatesDifferentOccurrencesBothRemain() {
        let first = UUID()
        let second = UUID()
        let pins = [
            pin(first, name: "Tokyo"),
            pin(second, name: "Tokyo"),
        ]
        let snap = DraftMapPins.snapshot(revision: 1, pins: pins)
        #expect(snap.pins.map(\.occurrenceID) == [first, second])
        #expect(snap.pins[0].latitude == snap.pins[1].latitude)
        #expect(snap.pins[0].longitude == snap.pins[1].longitude)
    }

    @Test("A time-text edit is an update, not a remove plus insert")
    func updateTimeTextEmitsUpdate() {
        let id = UUID()
        let old = DraftMapPins.snapshot(revision: 1, pins: [pin(id, timeText: "")])
        let edited = pin(id, timeText: "10:15")
        let new = DraftMapPins.snapshot(revision: 2, pins: [edited])
        #expect(DraftMapPins.diff(from: old, to: new) == [.update(edited)])
    }

    @Test("Deleting a stop emits remove for that occurrence")
    func deleteEmitsRemove() {
        let kept = UUID()
        let dropped = UUID()
        let old = DraftMapPins.snapshot(revision: 1, pins: [pin(kept), pin(dropped, name: "Shinagawa")])
        let new = DraftMapPins.snapshot(revision: 2, pins: [pin(kept)])
        #expect(DraftMapPins.diff(from: old, to: new) == [.remove(dropped)])
    }

    @Test("Reordering keeps every occurrence id")
    func reorderDoesNotDropIDs() {
        let first = UUID()
        let second = UUID()
        let alpha = pin(first, name: "A")
        let beta = pin(second, name: "B")
        let old = DraftMapPins.snapshot(revision: 1, pins: [alpha, beta])
        let new = DraftMapPins.snapshot(revision: 2, pins: [beta, alpha])
        let changes = DraftMapPins.diff(from: old, to: new)
        #expect(changes.isEmpty)
        #expect(new.pins.map(\.occurrenceID) == [second, first])
    }

    @Test("A pin with no coordinate and no clock text is kept as given")
    func nilCoordinatePinIsKept() {
        let id = UUID()
        let unplaced = pin(id, timeText: "", latitude: nil, longitude: nil)
        let snap = DraftMapPins.snapshot(revision: 3, pins: [unplaced])
        #expect(snap.pins == [unplaced])
        #expect(snap.pins[0].timeText.isEmpty)
    }

    @Test("Diff order is removes, then updates, then inserts")
    func diffOrderIsRemovesUpdatesInserts() {
        let removedFirst = UUID()
        let removedSecond = UUID()
        let updatedLater = UUID()
        let updatedEarlier = UUID()
        let inserted = UUID()
        let stable = pin(updatedEarlier, name: "B", timeText: "08:00")
        let old = DraftMapPins.snapshot(
            revision: 1,
            pins: [
                pin(removedFirst, name: "A"),
                stable,
                pin(removedSecond, name: "C"),
                pin(updatedLater, name: "D", timeText: "11:00"),
            ])
        let updatedLaterPin = pin(updatedLater, name: "D", timeText: "11:30")
        let updatedEarlierPin = pin(updatedEarlier, name: "B", timeText: "08:05")
        let insertedPin = pin(inserted, name: "E", timeText: "")
        let new = DraftMapPins.snapshot(
            revision: 2,
            pins: [updatedLaterPin, insertedPin, updatedEarlierPin])
        #expect(DraftMapPins.diff(from: old, to: new) == [
            .remove(removedFirst),
            .remove(removedSecond),
            .update(updatedLaterPin),
            .update(updatedEarlierPin),
            .insert(insertedPin),
        ])
    }
}
