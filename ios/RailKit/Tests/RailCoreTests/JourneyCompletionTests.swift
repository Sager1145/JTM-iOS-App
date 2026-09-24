import Foundation
import Testing

@testable import RailCore

struct JourneyCompletionTests {
    private static func train(
        id: String = "limited-7",
        date: String? = "2026-09-22",
        number: String = "Limited 7",
        company: String? = nil,
        routePolicy: RoutePolicy? = nil
    ) -> Train {
        Train(
            id: id,
            date: date,
            number: number,
            company: company,
            origin: "Alpha",
            destination: "Omega",
            visible: true,
            style: TrainStyle(color: "#123456"),
            routePolicy: routePolicy,
            stops: [
                Stop(
                    name: "Alpha",
                    n02StationCode: "A001",
                    departure: "09:00",
                    stopType: "origin",
                    rideSegment: true),
                Stop(
                    name: "Omega",
                    n02StationCode: "B001",
                    stopType: "destination",
                    rideSegment: false),
            ],
            region: "jp")
    }

    private static func response(
        id: String = "limited-7",
        body: String
    ) -> String {
        """
        {
          "trains": [{
            "id": "\(id)",
            "sources": [{
              "url": "https://rail.example/timetable",
              "explanation": "Official timetable and rolling-stock page"
            }],
            \(body)
          }]
        }
        """
    }

    @Test("eligibility requires endpoints, two identifying anchors, and a missing field")
    func eligibility() {
        let eligible = Self.train()
        let tooSparse = Self.train(date: nil, number: "")
        let undatedAndSparse = Self.train(date: Dates.undated, number: "")
        var missingEndpoint = eligible
        missingEndpoint.stops[1].name = ""
        var complete = eligible
        complete.numberEn = "Limited Seven"
        complete.trainType = "Limited Express"
        complete.vehicleType = "EMU-700"
        complete.company = "Example Rail"
        complete.direction = "down"
        complete.routePolicy = RoutePolicy(preferredLineNames: ["Main Line"])
        complete.stops[0].arrival = "08:58"
        complete.stops[0].platformNumber = 1
        complete.stops[1].arrival = "10:00"
        complete.stops[1].departure = "10:02"
        complete.stops[1].platformNumber = 2

        #expect(JourneyCompletion.isEligible(eligible))
        #expect(JourneyCompletion.isEligible(tooSparse) == false)
        #expect(JourneyCompletion.isEligible(undatedAndSparse) == false)
        #expect(JourneyCompletion.isEligible(missingEndpoint) == false)
        #expect(JourneyCompletion.isEligible(complete) == false)
    }

    @Test("prompt filters a mixed batch and omits styling, ride state, and station identity")
    func promptContainsOnlySafeEligibleContext() throws {
        let eligible = Self.train()
        let ineligible = Self.train(id: "sparse", date: nil, number: "")

        let prompt = try JourneyCompletion.prompt(
            trains: [eligible, ineligible],
            context: "The attached screenshot shows the same trip.")

        #expect(prompt.contains(#""id" : "limited-7""#))
        #expect(prompt.contains("The attached screenshot shows the same trip."))
        #expect(prompt.contains("sparse") == false)
        #expect(prompt.contains("ride_segment") == false)
        #expect(prompt.contains("n02_station_code") == false)
        #expect(prompt.contains("#123456") == false)
        #expect(prompt.contains("visible") == false)
    }

    @Test("valid fenced JSON fills only missing fields and preserves journey-owned data")
    func validMerge() throws {
        let original = Self.train(routePolicy: RoutePolicy(mode: "single_primary_route"))
        let json = Self.response(body: """
        "number_en": "Limited Seven",
        "train_type": "Limited Express",
        "vehicle_type": "EMU-700",
        "company": "Example Rail",
        "direction": "down",
        "line_names": ["Main Line"],
        "stops": [
          {"index": 0, "name": "Alpha", "platform_number": 1},
          {"index": 1, "name": "Omega", "arrival": "10:00", "platform_number": 2}
        ]
        """)

        let merged = try JourneyCompletion.merge(
            response: "```json\n\(json)\n```",
            into: [original])
        let result = try #require(merged.first)

        #expect(result.numberEn == "Limited Seven")
        #expect(result.trainType == "Limited Express")
        #expect(result.vehicleType == "EMU-700")
        #expect(result.company == "Example Rail")
        #expect(result.direction == "down")
        #expect(result.routePolicy?.preferredLineNames == ["Main Line"])
        #expect(result.routePolicy?.mode == "single_primary_route")
        #expect(result.stops[0].platformNumber == 1)
        #expect(result.stops[1].arrival == "10:00")
        #expect(result.stops[1].platformNumber == 2)
        #expect(result.id == original.id)
        #expect(result.date == original.date)
        #expect(result.origin == original.origin)
        #expect(result.destination == original.destination)
        #expect(result.region == original.region)
        #expect(result.visible == original.visible)
        #expect(result.style == original.style)
        #expect(result.stops.map(\.n02StationCode) == original.stops.map(\.n02StationCode))
        #expect(result.stops.map(\.stopType) == original.stops.map(\.stopType))
        #expect(result.stops.map(\.rideSegment) == original.stops.map(\.rideSegment))
    }

    @Test("line names create a canonical route policy when one is absent")
    func lineNamesCreateCanonicalPolicy() throws {
        let original = Self.train(routePolicy: nil)
        let merged = try JourneyCompletion.merge(
            response: Self.response(body: #""line_names": ["Main Line"]"#),
            into: [original])
        let policy = try #require(merged.first?.routePolicy)

        #expect(policy.mode == "single_primary_route")
        #expect(policy.jrOnly == false)
        #expect(policy.allowAlternatives == false)
        #expect(policy.allowBrowserStraightLineFallback == false)
        #expect(policy.allowedInstitutionTypeCodes == TrainValidation.defaultAllowedInstitutionTypeCodes)
        #expect(policy.preferredLineNames == ["Main Line"])
        #expect(policy.preferredOperatorNames == [])
        #expect(policy.institutionFilterMode == "soft")
    }

    @Test("route section line names reject conflicting completion and preserve identical suggestions",
          arguments: [nil, [], ["  "]] as [[String]?])
    func routeSectionLinesArePreserved(preferred: [String]?) throws {
        var original = Self.train(routePolicy: RoutePolicy(preferredLineNames: preferred))
        original.routeSections = [RouteSection(from: "Alpha", to: "Omega", lineNames: ["Existing Line"])]

        #expect(throws: JourneyCompletion.Error.conflictingValue(
            path: "trains[limited-7].line_names",
            existing: "Existing Line",
            suggested: "Different Line")) {
            try JourneyCompletion.merge(
                response: Self.response(body: #""line_names": ["Different Line"]"#),
                into: [original])
        }
        let merged = try JourneyCompletion.merge(
            response: Self.response(body: #""line_names": ["Existing Line"]"#),
            into: [original])
        #expect(merged == [original])
        #expect(try JourneyCompletion.prompt(trains: [original]).contains("Existing Line"))
    }

    @Test("a complete journey with section line names does not need line completion")
    func routeSectionLinesAreNotMissing() {
        var complete = Self.train(company: "Example Rail")
        complete.numberEn = "Limited Seven"
        complete.trainType = "Limited Express"
        complete.vehicleType = "EMU-700"
        complete.direction = "down"
        complete.routeSections = [RouteSection(from: "Alpha", to: "Omega", lineNames: ["Existing Line"])]
        complete.stops[0].platformNumber = 1
        complete.stops[1].arrival = "10:00"
        complete.stops[1].platformNumber = 2
        #expect(JourneyCompletion.isEligible(complete) == false)
    }

    @Test("an identical suggestion preserves an existing value")
    func existingValueIsPreserved() throws {
        let original = Self.train(company: "Example Rail")
        let merged = try JourneyCompletion.merge(
            response: Self.response(body: #""company": "Example Rail""#),
            into: [original])

        #expect(merged == [original])
    }

    @Test("first-stop arrival and last-stop departure are not treated as missing")
    func missingFieldExcludesEndpoints() {
        var complete = Self.train()
        complete.numberEn = "Limited Seven"
        complete.trainType = "Limited Express"
        complete.vehicleType = "EMU-700"
        complete.company = "Example Rail"
        complete.direction = "down"
        complete.routePolicy = RoutePolicy(preferredLineNames: ["Main Line"])
        complete.stops[0].platformNumber = 1
        complete.stops[1].arrival = "10:00"
        complete.stops[1].platformNumber = 2
        // stops[0].arrival and stops[1].departure stay nil: they are endpoints, not missing.

        #expect(JourneyCompletion.isEligible(complete) == false)
    }

    @Test("an equivalent time format is treated as the same value, not a conflict")
    func timeEquivalencePreservesExistingValue() throws {
        let original = Self.train()

        let merged = try JourneyCompletion.merge(
            response: Self.response(body: #""stops": [{"index": 0, "name": "Alpha", "departure": "9:00"}]"#),
            into: [original])

        #expect(merged.first?.stops[0].departure == "09:00")
    }

    @Test("an imported empty string is treated as no existing value")
    func emptyStringTreatedAsAbsent() throws {
        var firstStopEmptyArrival = Self.train()
        firstStopEmptyArrival.stops[0].departure = nil
        firstStopEmptyArrival.stops[0].arrival = ""
        let firstMerged = try JourneyCompletion.merge(
            response: Self.response(body: #""stops": [{"index": 0, "name": "Alpha", "departure": "09:05"}]"#),
            into: [firstStopEmptyArrival])
        #expect(firstMerged.first?.stops[0].departure == "09:05")

        var lastStopEmptyDeparture = Self.train()
        lastStopEmptyDeparture.stops[1].departure = ""
        let lastMerged = try JourneyCompletion.merge(
            response: Self.response(body: #""stops": [{"index": 1, "name": "Omega", "arrival": "10:05"}]"#),
            into: [lastStopEmptyDeparture])
        #expect(lastMerged.first?.stops[1].arrival == "10:05")
    }

    @Test("a row with only null suggestions is skipped rather than rejected")
    func allNullRowIsSkipped() throws {
        let original = Self.train()
        let second = Self.train(id: "limited-9")
        let response = """
        {
          "trains": [
            {
              "id": "limited-7",
              "sources": [],
              "number_en": null,
              "stops": []
            },
            {
              "id": "limited-9",
              "sources": [{"url": "https://rail.example/timetable", "explanation": "Timetable"}],
              "company": "Example Rail"
            }
          ]
        }
        """

        let merged = try JourneyCompletion.merge(response: response, into: [original, second])

        #expect(merged[0] == original)
        #expect(merged[1].company == "Example Rail")
    }

    @Test("an all-null stop row with a mismatched name is ignored")
    func allNullRowWithMismatchedNameIsIgnored() throws {
        let original = Self.train()

        let merged = try JourneyCompletion.merge(
            response: Self.response(
                body: #""stops": [{"index": 0, "name": "Totally Different"}], "company": "Example Rail""#),
            into: [original])

        #expect(merged.first?.company == "Example Rail")
        #expect(merged.first?.stops == original.stops)
    }

    @Test("an input stop name with surrounding whitespace matches a trimmed suggested name")
    func stopNameMatchesAfterTrimming() throws {
        var padded = Self.train()
        padded.stops[0].name = "  Alpha  "

        let merged = try JourneyCompletion.merge(
            response: Self.response(body: #""stops": [{"index": 0, "name": "Alpha", "platform_number": 3}]"#),
            into: [padded])

        #expect(merged.first?.stops[0].platformNumber == 3)
    }

    @Test("a conflicting suggestion is rejected atomically")
    func conflictIsRejected() {
        let original = Self.train(company: "Recorded Rail")

        #expect(throws: JourneyCompletion.Error.conflictingValue(
            path: "trains[limited-7].company",
            existing: "Recorded Rail",
            suggested: "Different Rail")) {
            try JourneyCompletion.merge(
                response: Self.response(body: #""company": "Different Rail""#),
                into: [original])
        }
    }

    @Test("malformed and unknown response structures are rejected")
    func malformedResponsesAreRejected() {
        let original = Self.train()

        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(response: "not json", into: [original])
        }
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(body: #""unexpected": "value""#),
                into: [original])
        }
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(id: "unknown", body: #""company": "Example Rail""#),
                into: [original])
        }
    }

    @Test("invalid stop references, times, platforms, and evidence are rejected")
    func invalidSuggestionsAreRejected() {
        let original = Self.train()
        let cases = [
            Self.response(body: #""stops": [{"index": 0, "name": "Wrong", "departure": "09:02"}]"#),
            Self.response(body: #""stops": [{"index": 1, "name": "Omega", "arrival": "10:99"}]"#),
            Self.response(body: #""stops": [{"index": 1, "name": "Omega", "platform_number": -1}]"#),
            Self.response(body: #""stops": [{"index": 0, "name": "Alpha", "arrival": "08:58"}]"#),
            Self.response(body: #""stops": [{"index": 1, "name": "Omega", "departure": "10:02"}]"#),
            Self.response(body: #""stops": [{"index": 1, "name": "Omega", "arrival": "08:59"}]"#),
            """
            {"trains":[{"id":"limited-7","sources":[],"company":"Example Rail"}]}
            """,
        ]

        for response in cases {
            #expect(throws: JourneyCompletion.Error.self) {
                try JourneyCompletion.merge(response: response, into: [original])
            }
        }
    }

    @Test("overnight suffixes are accepted but trailing time text is rejected")
    func strictOvernightTimes() throws {
        var original = Self.train()
        original.stops[0].departure = "23:55"

        let merged = try JourneyCompletion.merge(
            response: Self.response(
                body: #""stops": [{"index": 1, "name": "Omega", "arrival": "00:10 + 1"}]"#),
            into: [original])
        #expect(merged.first?.stops[1].arrival == "00:10 + 1")

        let multiDay = try JourneyCompletion.merge(
            response: Self.response(
                body: #""stops": [{"index": 1, "name": "Omega", "arrival": "09:30+10"}]"#),
            into: [original])
        #expect(multiDay.first?.stops[1].arrival == "09:30+10")

        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(
                    body: #""stops": [{"index": 1, "name": "Omega", "arrival": "00:10+1 later"}]"#),
                into: [original])
        }
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(
                    body: #""stops": [{"index": 1, "name": "Omega", "arrival": "09:30+367"}]"#),
                into: [original])
        }
    }

    @Test("new endpoint times cannot create both arrival and departure")
    func endpointTimePairsAreRejectedOnlyWhenSuggested() throws {
        var firstArrival = Self.train()
        firstArrival.stops[0].arrival = "08:58"
        firstArrival.stops[0].departure = nil
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(
                    body: #""stops": [{"index": 0, "name": "Alpha", "departure": "09:00"}]"#),
                into: [firstArrival])
        }

        var lastDeparture = Self.train()
        lastDeparture.stops[1].departure = "10:05"
        #expect(throws: JourneyCompletion.Error.self) {
            try JourneyCompletion.merge(
                response: Self.response(
                    body: #""stops": [{"index": 1, "name": "Omega", "arrival": "10:00"}]"#),
                into: [lastDeparture])
        }

        var oddExistingRecord = Self.train()
        oddExistingRecord.stops[0].arrival = "08:58"
        let metadataOnly = try JourneyCompletion.merge(
            response: Self.response(body: #""company": "Example Rail""#),
            into: [oddExistingRecord])
        #expect(metadataOnly.first?.company == "Example Rail")
        #expect(metadataOnly.first?.stops[0].arrival == "08:58")
    }

    @Test("duplicate train IDs and duplicate stop references are rejected")
    func duplicateReferencesAreRejected() {
        let original = Self.train()
        let duplicateStop = Self.response(body: """
        "stops": [
          {"index": 1, "name": "Omega", "arrival": "10:00"},
          {"index": 1, "name": "Omega", "platform_number": 2}
        ]
        """)

        #expect(throws: JourneyCompletion.Error.duplicateInputTrainID("limited-7")) {
            try JourneyCompletion.merge(response: Self.response(body: #""company": "Rail""#), into: [original, original])
        }
        #expect(throws: JourneyCompletion.Error.duplicateStopReference(trainID: "limited-7", index: 1)) {
            try JourneyCompletion.merge(response: duplicateStop, into: [original])
        }
    }

    @Test("default prompt rejects a timed station the research rule skips; a caller gate can accept it")
    func callerEligibilityCanPromptAResearchIneligibleTrain() throws {
        let timed = Self.train(date: nil, number: "")
        #expect(JourneyCompletion.isEligible(timed) == false)
        #expect(timed.stops.contains { ($0.n02StationCode ?? "").isEmpty == false })
        #expect(throws: JourneyCompletion.Error.noEligibleTrains) {
            try JourneyCompletion.prompt(trains: [timed])
        }

        let prompt = try JourneyCompletion.prompt(trains: [timed]) { train in
            EditorAIEligibility.denial(
                stops: train.stops.map { stop in
                    let code = stop.n02StationCode ?? ""
                    func field(_ text: String?) -> EditorTimeInput {
                        guard let text, text.isEmpty == false else {
                            return EditorTime.input("", confirmed: false)
                        }
                        return EditorTime.input(text, confirmed: true)
                    }
                    return EditorAIStop(
                        occurrenceID: UUID(),
                        stationResolved: code.isEmpty == false,
                        arrival: field(stop.arrival),
                        departure: field(stop.departure))
                },
                providerAvailable: true,
                requestInFlight: false) == nil
        }
        #expect(prompt.isEmpty == false)
        #expect(prompt.contains("Alpha"))
    }

    @Test("request eligibility requires a catalog station and valid time on the same stop")
    func requestEligibilityUsesCatalogIdentityAndCorrespondingTime() {
        let catalog = Self.catalog()
        var train = Self.train(date: nil, number: "")
        train.stops[0].n02StationCode = "TOK"
        train.stops[0].name = "東京"
        train.origin = "東京"
        train.stops[1].n02StationCode = "OSA"
        train.stops[1].name = "新大阪"
        train.destination = "新大阪"

        #expect(JourneyCompletion.isRequestEligible(train, catalog: catalog))

        train.stops[0].n02StationCode = "NOT-IN-CATALOG"
        #expect(JourneyCompletion.isRequestEligible(train, catalog: catalog) == false)

        train.stops[0].departure = nil
        train.stops[1].arrival = "not a time"
        #expect(JourneyCompletion.requestDenial(train: train, catalog: catalog) == .invalidTime)

        train.stops[0].n02StationCode = "TOK"
        train.stops[0].departure = nil
        train.stops[1].n02StationCode = "NOT-IN-CATALOG"
        train.stops[1].arrival = "10:00"
        #expect(JourneyCompletion.requestDenial(train: train, catalog: catalog) == .timeNotOnThatStation)
    }

    @Test("catalog request eligibility accepts a station from another catalog region")
    func requestEligibilitySearchesCatalogRegions() {
        let catalog = EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "us", lineID: "maple-us", name: "Maple Leaf", stations: [
                    EditorCatalogStationSource(
                        sourceCode: "NYP", name: "New York", longitude: -73.993, latitude: 40.750),
                ]),
            EditorCatalogLineSource(
                regionCode: "ca", lineID: "maple-ca", name: "Maple Leaf", stations: [
                    EditorCatalogStationSource(
                        sourceCode: "TWO", name: "Toronto", longitude: -79.380, latitude: 43.645),
                ]),
        ])
        let train = Train(
            id: "cross-border", number: "", origin: "New York", destination: "Toronto",
            visible: true,
            stops: [
                Stop(
                    name: "New York", n02StationCode: "NYP", departure: "7:15",
                    stopType: "origin", rideSegment: true),
                Stop(
                    name: "Toronto", n02StationCode: "TWO", arrival: nil,
                    stopType: "destination", rideSegment: true),
            ],
            region: "ca")

        #expect(JourneyCompletion.requestDenial(train: train, catalog: catalog) == nil)
        #expect(JourneyCompletion.isRequestEligible(train, catalog: catalog))
    }

    @Test("pasted text is locally extracted and only catalog-confirmed stations build a train")
    func pastedTextBuildsConfirmedStructuredDraft() throws {
        let catalog = Self.catalog()
        let seed = Train(
            id: "draft", number: "", origin: "", destination: "", visible: true,
            stops: [
                Stop(name: "", stopType: "origin", rideSegment: true),
                Stop(name: "", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
        let draft = JourneyCompletion.rawDraft(
            text: """
            2026-09-24
            列車: ひかり501号
            東京 09:03 発 14番線
            新大阪 11:57 着
            """,
            catalog: catalog,
            regionCode: "jp",
            seed: seed)

        #expect(draft.date == "2026-09-24")
        #expect(draft.service == "ひかり501号")
        #expect(draft.stops.count == 2)
        #expect(draft.stops[0].departure == "9:03")
        #expect(draft.stops[0].platformNumber == 14)
        #expect(draft.stops[1].arrival == "11:57")
        #expect(draft.stops[0].automaticSelection == StationKey(regionCode: "jp", sourceCode: "TOK"))

        #expect(draft.train(seed: seed, selections: [:], catalog: catalog) == nil)
        let selections = Dictionary(uniqueKeysWithValues: draft.stops.compactMap { stop in
            stop.automaticSelection.map { (stop.id, $0) }
        })
        let train = try #require(draft.train(seed: seed, selections: selections, catalog: catalog))
        #expect(train.number == "ひかり501号")
        #expect(train.origin == "東京")
        #expect(train.destination == "新大阪")
        #expect(train.stops.map(\.n02StationCode) == ["TOK", "OSA"])
        #expect(train.routePolicy == nil)
        #expect(train.routeSections == nil)
        #expect(JourneyCompletion.isRequestEligible(train, catalog: catalog))
    }

    @Test("ambiguous pasted station names remain unselected for confirmation")
    func ambiguousStationRequiresSelection() {
        let catalog = EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "a", name: "A", stations: [
                    EditorCatalogStationSource(
                        sourceCode: "CENTRAL-A", name: "中央", longitude: 139, latitude: 35),
                ]),
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "b", name: "B", stations: [
                    EditorCatalogStationSource(
                        sourceCode: "CENTRAL-B", name: "中央", longitude: 135, latitude: 34),
                    EditorCatalogStationSource(
                        sourceCode: "WEST", name: "西", longitude: 135.1, latitude: 34),
                ]),
        ])
        let seed = Self.train(id: "draft", date: nil, number: "")
        let draft = JourneyCompletion.rawDraft(
            text: "中央 9:00 発\n西 10:00 着",
            catalog: catalog,
            regionCode: "jp",
            seed: seed)

        #expect(draft.stops.first?.candidates.count == 2)
        #expect(draft.stops.first?.automaticSelection == nil)
    }

    private static func catalog() -> EditorCatalog {
        EditorCatalogBuilder.build([
            EditorCatalogLineSource(
                regionCode: "jp", lineID: "shinkansen", name: "東海道新幹線",
                stations: [
                    EditorCatalogStationSource(
                        sourceCode: "TOK", name: "東京", nameRoma: "Tokyo",
                        longitude: 139.767, latitude: 35.681),
                    EditorCatalogStationSource(
                        sourceCode: "OSA", name: "新大阪", nameRoma: "Shin-Osaka",
                        longitude: 135.500, latitude: 34.733),
                ])
        ])
    }
}
