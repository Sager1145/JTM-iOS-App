#if DEBUG
import RailCore
import RailPresentation
import SwiftUI

/// Exercise production detail surfaces without depending on a saved library.
struct LongJourneyDetailTestView: View {
    let mode: String
    @State private var closed = false
    @State private var editedTrain: Train?
    private let train: Train

    init(mode: String) {
        self.mode = mode
        let longStops = (0..<2_048).map {
            Stop(name: "Long journey station \($0)", arrival: "10:00", departure: "10:01")
        }
        let sections = (0..<longStops.count - 1).map {
            RouteSection(from: longStops[$0].name, to: longStops[$0 + 1].name,
                         lineNames: ["Test line \($0 % 2)"])
        }
        let stops = mode == "advanced" ? Array(longStops.prefix(2)) : longStops
        if mode == "partial" {
            train = Train(id: "partial-detail-test", number: "Partial ride", origin: "Origin A", destination: "Destination D",
                          stops: [
                            Stop(name: "Origin A", platformNumber: 1, departure: "08:00", stopType: "origin", rideSegment: false),
                            Stop(name: "Boarding B", platformNumber: 2, departure: "08:30", stopType: "passenger_stop", rideSegment: true),
                            Stop(name: "Alighting C", platformNumber: 3, arrival: "09:00", stopType: "passenger_stop", rideSegment: true),
                            Stop(name: "Destination D", platformNumber: 4, arrival: "09:30", stopType: "destination", rideSegment: false),
                          ])
        } else if mode == "update" {
            train = Train(id: "long-detail-test", number: "Spelling edit", origin: "é", destination: "B",
                          routeSections: [RouteSection(from: "é", to: "B", lineNames: ["Original line"])],
                          stops: [Stop(name: "é"), Stop(name: "B")])
        } else {
            train = Train(id: "long-detail-test", number: "Long journey", origin: stops[0].name,
                          destination: stops[stops.count - 1].name,
                          routeSections: Array(sections.reversed()), stops: stops)
        }
    }

    var body: some View {
        if closed {
            Text("Journey closed").accessibilityIdentifier("longJourneyClosed")
        } else if mode == "card" {
            RideCard(train: train, presentation: .init(title: .value(train.number)),
                     onClose: { closed = true }, onPrimary: { _ in }, onSecondary: { _ in })
        } else {
            NavigationStack {
                RideDetailView(train: editedTrain ?? train)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { closed = true }
                                .accessibilityIdentifier("longJourneyClose")
                        }
                        if mode == "update" {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Change spelling") {
                                    var updated = train
                                    updated.stops[0].name = "e\u{301}"
                                    editedTrain = updated
                                }
                                .accessibilityIdentifier("longJourneyUpdate")
                            }
                        }
                    }
            }
        }
    }
}
#endif
