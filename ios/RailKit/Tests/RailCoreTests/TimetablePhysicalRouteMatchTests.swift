import Testing
@testable import RailCore

@Suite("Verified timetable physical subroutes")
struct TimetablePhysicalRouteMatchTests {
    @Test func unrelatedStationOccurrencesDoNotExhaustMatchingBudget() throws {
        let train = journey(["B", "D"], departure: "10:10", arrival: "10:30")
        let unrelated = (0..<5_100).map {
            fixture(id: "unrelated-\($0)", codes: ["W", "X", "Y", "Z"])
        }
        #expect(try matched(train, trips: unrelated + [fixture()]).provenance.tripID == "trip")
    }

    @Test func reusedStationIndexKeepsRepeatedVisitsAndUncertainCompetitors() throws {
        let repeated = TimetablePhysicalRouteMatch.CandidateIndex(trips: [
            fixture(codes: ["A", "B", "A", "D"]),
            fixture(id: "other-stations", codes: ["W", "X", "Y", "Z"])
        ])
        let untimed = journey(["A", "D"])
        #expect(TimetablePhysicalRouteMatch.resolve(for: untimed,
            routeSections: TrainValidation.routeSectionsForSolving(for: untimed), indexedBy: [repeated]) == .ambiguous)
        let timed = journey(["A", "D"], departure: "10:20", arrival: "10:30")
        let outcome = TimetablePhysicalRouteMatch.resolve(for: timed,
            routeSections: TrainValidation.routeSectionsForSolving(for: timed), indexedBy: [repeated])
        guard case .matched(let match) = outcome else {
            Issue.record("Timed repeated visit lost its occurrence: \(outcome)")
            return
        }
        #expect(match.passengerCallIndices == [2, 3])
        #expect(match.sections[0].sectionCodes == ["AD"])
        let uncertain = TimetablePhysicalRouteMatch.CandidateIndex(trips: [
            fixture(seconds: [32_400, 33_000, 33_600, 34_200]),
            fixture(id: "possible", seconds: [32_460, 33_060, 33_660, 34_260], timeAccuracy: "unknown")
        ])
        let clocked = journey(["A", "D"], departure: "09:00", arrival: "09:30")
        #expect(TimetablePhysicalRouteMatch.resolve(for: clocked,
            routeSections: TrainValidation.routeSectionsForSolving(for: clocked), indexedBy: [uncertain]) == .unsupported)
    }

    @Test func stationIndexDoesNotHideUnsupportedSectionBoundary() {
        let train = journey(["B", "D"])
        let sections = [RouteSection(fromN02StationCode: "B", toN02StationCode: "unknown"),
                        RouteSection(fromN02StationCode: "unknown", toN02StationCode: "D")]
        let index = TimetablePhysicalRouteMatch.CandidateIndex(trips: [fixture()])
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
            indexedBy: [index]) == .unsupported)
    }

    @Test func partialJourneyKeepsOriginalSectionsAndMetadata() throws {
        let trip = fixture()
        let train = journey(["B", "D"], departure: "10:10", arrival: "10:30")
        let section = RouteSection(from: "B", to: "D", fromN02StationCode: "B",
                                   toN02StationCode: "D", number: "1", name: "Express")
        let result = try matched(train, sections: [section], trips: [trip])
        #expect(result.passengerCallIndices == [1, 3])
        #expect(result.sections[0].sectionCodes == ["BC", "CD"])
        #expect(result.sections[0].lineIDs == ["L"])
        #expect(result.enrichedRouteSections[0].name == "Express")
        #expect(result.enrichedRouteSections[0].number == "1")
        #expect(result.enrichedRouteSections[0].fromN02StationCode == "B")
        #expect(result.enrichedRouteSections[0].toN02StationCode == "D")
        #expect(result.provenance.tripID == "trip")
        #expect(train.stops.count == 2)
    }

    @Test func allRecordedCallsConstrainTheRunTogether() throws {
        let train = journey(["A", "B", "D"], departure: "10:00", arrival: "10:30")
        let sections = TrainValidation.routeSectionsForSolving(for: train)
        let result = try matched(train, sections: sections, trips: [fixture()])
        #expect(result.sections.map(\.sectionCodes) == [["AB"], ["BC", "CD"]])
        var wrong = train
        wrong.stops[1].departure = "10:11"
        #expect(TimetablePhysicalRouteMatch.resolve(for: wrong, routeSections: sections,
                                                   among: [fixture()]) == .unavailable)
    }

    @Test func nextDayBoardingAndMidnightRolloverUseOccurrenceSeconds() throws {
        let trip = fixture(seconds: [85_800, 87_000, 88_200, 89_400])
        var nextDay = journey(["B", "D"], departure: "00:10", arrival: "00:50")
        nextDay.date = "2026-09-30"
        let result = try matched(nextDay, trips: [trip])
        #expect(result.serviceDate == "2026-09-29")
        #expect(result.sections[0].sectionCodes == ["BC", "CD"])
        let overnight = journey(["A", "D"], departure: "23:50", arrival: "00:50")
        #expect(try matched(overnight, trips: [trip]).passengerCallIndices == [0, 3])
        let extended = journey(["A", "D"], departure: "23:50", arrival: "24:50")
        #expect(try matched(extended, trips: [trip]).passengerCallIndices == [0, 3])
        nextDay.date = "2026-10-01"
        #expect(TimetablePhysicalRouteMatch.resolve(for: nextDay,
            routeSections: TrainValidation.routeSectionsForSolving(for: nextDay), among: [trip]) == .unavailable)
    }

    @Test func repeatedStationsRetainOccurrenceOrderAndAmbiguity() throws {
        let trip = fixture(codes: ["A", "B", "A", "D"])
        let timed = journey(["A", "D"], departure: "10:20", arrival: "10:30")
        #expect(try matched(timed, trips: [trip]).sections[0].sectionCodes == ["AD"])
        let untimed = journey(["A", "D"])
        #expect(TimetablePhysicalRouteMatch.resolve(for: untimed,
            routeSections: TrainValidation.routeSectionsForSolving(for: untimed), among: [trip]) == .ambiguous)
        let repeated = journey(["A", "B", "A", "D"])
        #expect(try matched(repeated, trips: [trip]).passengerCallIndices == [0, 1, 2, 3])
    }

    @Test func explicitSelectionCannotBeOverwritten() throws {
        let train = journey(["B", "D"])
        var section = TrainValidation.routeSectionsForSolving(for: train)[0]
        section.sectionCodes = ["user-choice"]
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: [section],
                                                   among: [fixture()]) == .unavailable)
        section.sectionCodes = ["BC", "CD"]
        #expect(try matched(train, sections: [section], trips: [fixture()])
            .enrichedRouteSections[0].sectionCodes == ["BC", "CD"])
    }

    @Test func missingPhysicalProofAndCompetingOccurrencesFailClosed() {
        let train = journey(["B", "D"])
        let sections = TrainValidation.routeSectionsForSolving(for: train)
        var incomplete = fixture()
        incomplete.physicalRouteSections.removeLast()
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
                                                   among: [incomplete]) == .unsupported)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
                                                   among: [fixture(), fixture(id: "other")]) == .ambiguous)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
                                                   among: [fixture(), incomplete]) == .unsupported)
    }

    @Test func suppliedLineOperatorServiceAndTimeConstraintsMustAllAgree() {
        let trip = fixture()
        var train = journey(["B", "D"])
        let base = TrainValidation.routeSectionsForSolving(for: train)[0]
        for section in [RouteSection(fromN02StationCode: "B", toN02StationCode: "D", lineIDs: ["wrong"]),
                        RouteSection(fromN02StationCode: "B", toN02StationCode: "D", lineNames: ["wrong"]),
                        RouteSection(fromN02StationCode: "B", toN02StationCode: "D", operatorNames: ["wrong"]),
                        RouteSection(fromN02StationCode: "B", toN02StationCode: "D", number: "2")] {
            let outcome = TimetablePhysicalRouteMatch.resolve(for: train, routeSections: [section], among: [trip])
            if case .matched = outcome { Issue.record("A conflicting constraint produced a physical route") }
        }
        train.company = "JR西日本"
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: [base], among: [trip]) == .unavailable)
        train.company = nil
        train.number = "Express 2"
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: [base], among: [trip]) == .unavailable)
        train.number = "Express 1"
        train.stops[0].departure = "10:10 garbage"
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: [base], among: [trip]) == .unsupported)
    }

    @Test func unsupportedStationBoundariesAndFactCompletenessAreNotProof() {
        let train = journey(["B", "D"])
        let sections = [RouteSection(fromN02StationCode: "B", toN02StationCode: "unknown"),
                        RouteSection(fromN02StationCode: "unknown", toN02StationCode: "D")]
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
                                                   among: [fixture()]) == .unsupported)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train,
            routeSections: TrainValidation.routeSectionsForSolving(for: train),
            among: [fixture(verified: false)]) == .unsupported)
    }

    @Test func originalBoundarySplitsRemainSeparateAndSourceOffsetsAreChecked() throws {
        let train = journey(["A", "D"], departure: "10:00", arrival: "10:30")
        let sections = [RouteSection(fromN02StationCode: "A", toN02StationCode: "C"),
                        RouteSection(fromN02StationCode: "C", toN02StationCode: "D")]
        #expect(try matched(train, sections: sections, trips: [fixture()]).sections.map(\.sectionCodes)
            == [["AB", "BC"], ["CD"]])
        let overnight = fixture(seconds: [85_800, 87_000, 88_200, 89_400])
        var wrongDate = journey(["B", "D"], departure: "00:10", arrival: "00:50")
        #expect(TimetablePhysicalRouteMatch.resolve(for: wrongDate,
            routeSections: TrainValidation.routeSectionsForSolving(for: wrongDate), among: [overnight]) == .unavailable)
        wrongDate.date = "2026-09-30"
        wrongDate.stops[1].arrival = "00:50 +1"
        #expect(TimetablePhysicalRouteMatch.resolve(for: wrongDate,
            routeSections: TrainValidation.routeSectionsForSolving(for: wrongDate), among: [overnight]) == .unavailable)
    }

    @Test func staleOrUnverifiedIdentityCannotProduceAnApplicableRoute() {
        let train = journey(["B", "D"])
        let original = fixture()
        var missingIdentity = train
        missingIdentity.stops[0].n02StationCode = nil
        #expect(TimetablePhysicalRouteMatch.resolve(for: missingIdentity,
            routeSections: TrainValidation.routeSectionsForSolving(for: missingIdentity), among: [original]) == .unsupported)
        var unsupportedMetadata = train
        unsupportedMetadata.vehicleType = "Unverified formation"
        #expect(TimetablePhysicalRouteMatch.resolve(for: unsupportedMetadata,
            routeSections: TrainValidation.routeSectionsForSolving(for: unsupportedMetadata), among: [original]) == .unsupported)
        var passingCall = train
        passingCall.stops[0].stopType = "pass_through"
        #expect(TimetablePhysicalRouteMatch.resolve(for: passingCall,
            routeSections: TrainValidation.routeSectionsForSolving(for: passingCall), among: [original]) == .unsupported)
    }

    @Test func unrelatedTripWithMissingConstraintEvidenceDoesNotBlockMatchingRun() throws {
        var train = journey(["B", "D"], departure: "10:10", arrival: "10:30")
        train.direction = "down"
        let otherStations = fixture(id: "unrelated", codes: ["W", "X", "Y", "Z"], direction: nil)
        let otherClocks = fixture(id: "other-time", seconds: [39_600, 40_200, 40_800, 41_400], direction: nil)
        #expect(try matched(train, trips: [fixture(), otherStations, otherClocks]).provenance.tripID == "trip")
        #expect(TimetablePhysicalRouteMatch.resolve(for: train,
            routeSections: TrainValidation.routeSectionsForSolving(for: train),
            among: [fixture(), fixture(id: "unverified-direction", direction: nil)]) == .unsupported)
    }

    @Test(arguments: [Optional("approximate"), Optional("unknown"), nil])
    func uncertainClockFactsNeitherProveNorExcludeAnOccurrence(accuracy: String?) {
        let train = journey(["A", "D"], departure: "09:00", arrival: "09:30")
        let sections = TrainValidation.routeSectionsForSolving(for: train)
        let uncertainSameClock = fixture(seconds: [32_400, 33_000, 33_600, 34_200], timeAccuracy: accuracy)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
            among: [uncertainSameClock]) == .unsupported)
        let verified = fixture(seconds: [32_400, 33_000, 33_600, 34_200])
        let uncertainOtherClock = fixture(id: "potential-competitor",
            seconds: [32_460, 33_060, 33_660, 34_260], timeAccuracy: accuracy)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
            among: [verified, uncertainOtherClock]) == .unsupported)
    }

    @Test(arguments: [Optional("approximate"), Optional("unknown"), nil])
    func uncertainUntimedFirstVisitCannotExcludeAServiceDay(accuracy: String?) {
        var train = journey(["A", "D"])
        train.date = "2026-09-30"
        let sections = TrainValidation.routeSectionsForSolving(for: train)
        let uncertain = fixture(timeAccuracy: accuracy)
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
            among: [uncertain]) == .unsupported)
        let verifiedNextDay = fixture(seconds: [122_400, 123_000, 123_600, 124_200])
        #expect(TimetablePhysicalRouteMatch.resolve(for: train, routeSections: sections,
            among: [verifiedNextDay, uncertain]) == .unsupported)
    }

    @Test func exactAccuracyCanEstablishPublishedClockIdentity() throws {
        let train = journey(["A", "D"], departure: "09:00", arrival: "09:30")
        #expect(try matched(train, trips: [fixture(
            seconds: [32_400, 33_000, 33_600, 34_200], timeAccuracy: "exact")]).provenance.tripID == "trip")
    }

    @Test func appliedEvidenceInvalidatesWhenTimetableRevisionOrContentChanges() throws {
        let train = journey(["A", "B", "C", "D"])
        let sections = TrainValidation.routeSectionsForSolving(for: train)
        let trip = fixture()
        let evidence = try #require(TimetablePhysicalRouteMatch.appliedEvidence(
            trip: trip, train: train, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1"))
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            evidence, train: train, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1")?.provenance.tripID == "trip")
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            evidence, train: train, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-2") == nil)
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            evidence, train: train, sections: sections,
            railRevision: "rail-2", timetableRevision: "tt-1") == nil)
        var edited = train
        edited.stops[0].departure = "10:01"
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            evidence, train: edited, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1") == nil)
        var dated = train
        dated.date = "2026-09-30"
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            evidence, train: dated, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1") == nil)
        #expect(TimetablePhysicalRouteMatch.appliedEvidence(
            trip: trip, train: dated, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1") == nil)
        var confirmed = train
        confirmed.routeConfirmation = .confirmed
        #expect(TimetablePhysicalRouteMatch.reusableAppliedMatch(
            nil, train: confirmed, sections: sections,
            railRevision: "rail-1", timetableRevision: "tt-1") == nil)
        #expect(TimetablePhysicalRouteMatch.appliedEvidence(
            trip: trip, train: train, sections: sections,
            railRevision: nil, timetableRevision: "tt-1") == nil)
    }

    private func matched(_ train: Train, sections: [RouteSection]? = nil,
                         trips: [TrainTimetableDatabase.Trip]) throws -> TimetablePhysicalRouteMatch.Match {
        let result = TimetablePhysicalRouteMatch.resolve(for: train,
            routeSections: sections ?? TrainValidation.routeSectionsForSolving(for: train), among: trips)
        guard case .matched(let match) = result else {
            Issue.record("Expected verified physical subroute, got \(result)")
            throw MatchError.noMatch
        }
        return match
    }

    private enum MatchError: Error { case noMatch }

    private func journey(_ codes: [String], departure: String? = nil, arrival: String? = nil) -> Train {
        var stops = codes.map { Stop(name: $0, n02StationCode: $0, rideSegment: true) }
        stops[0].departure = departure
        stops[stops.count - 1].arrival = arrival
        return Train(id: "journey", date: "2026-09-29", number: "Express 1",
                     origin: codes[0], destination: codes.last!, stops: stops, region: "jp")
    }

    private func fixture(id: String = "trip", codes: [String] = ["A", "B", "C", "D"],
                         seconds: [Int] = [36_000, 36_600, 37_200, 37_800],
                         verified: Bool = true, direction: String? = "down",
                         timeAccuracy: String? = "minute") -> TrainTimetableDatabase.Trip {
        let facts = ["identity", "train_number", "operator", "validity_calendar", "origin_destination",
                     "stops", "times", "route_lines", "station_refs", "provenance"]
        let calls = codes.enumerated().map { index, code in
            TrainTimetableDatabase.StopTime(sequence: index, station: .init(
                id: code, name: code, referenceKind: .currentN02, currentSourceCode: code,
                railHistoryID: nil, validFrom: nil, validUntil: nil),
                arrivalTime: nil, departureTime: nil, arrivalSeconds: seconds[index],
                departureSeconds: seconds[index], dayOffset: seconds[index] / 86_400,
                arrivalDayOffset: seconds[index] / 86_400, departureDayOffset: seconds[index] / 86_400,
                callType: index == 0 ? "origin" : index == codes.count - 1 ? "destination" : "passenger_stop",
                pickupAllowed: true, dropoffAllowed: true, platform: nil, timeAccuracy: timeAccuracy)
        }
        var trip = TrainTimetableDatabase.Trip(id: id, serviceDate: "2026-09-29",
            timetableVersionID: "edition", timetableEditionName: "edition", service: .init(
                id: "express", canonicalName: "Express", englishName: "Express", serviceClass: "limited_express",
                historicalGeneration: 0, firstVerifiedDate: nil, lastVerifiedDate: nil, jrScope: "jr",
                matchingName: nil), calendarID: "calendar", trainNumber: "1M", publicNumber: "1", direction: direction,
            serviceClass: "limited_express", operationGroupID: nil, notes: nil, timetableCompleteness: .verified,
            factCompleteness: Dictionary(uniqueKeysWithValues: facts.map { ($0, verified ? .verified : .unknown) }),
            stops: calls, timetableSymbols: [], lineSegments: [], operatorSegments: [.init(
                fromSequence: 0, toSequence: codes.count - 1, operatorID: "jr-east", displayName: "JR東日本")])
        trip.physicalRouteSections = zip(codes, codes.dropFirst()).map { pair in
            RouteSection(from: pair.0, to: pair.1, fromN02StationCode: pair.0, toN02StationCode: pair.1,
                         lineNames: ["Line"], operatorNames: ["JR東日本"], lineIDs: ["L"], sectionCodes: [pair.0 + pair.1])
        }
        return trip
    }
}
