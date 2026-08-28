import Foundation

// =========================================================================
//  TransferGuideTrains.swift — a parsed screenshot as canonical records.
//
//  **Not a port**, for the same reason ``TransferGuide`` is not.
//
//  Three jobs, and they are separate because only the first one is a guess:
//
//    1. WHICH STATION. A screenshot spells `森(北海道)`; the rail package
//       spells `森`, and it also spells the OTHER 森 in Mie, and 大宮 exists
//       four times over. The name alone cannot answer it, so the answer comes
//       from the sequence: consecutive calls on one ride are near each other,
//       so the cheapest chain through the whole journey is the right one.
//       ``resolve(names:hints:index:)`` is that chain.
//
//    2. WHICH LINE. Once two neighbouring calls have station codes, the lines
//       they SHARE are a short list, and a leg that says 新幹線 on its face
//       cannot be on a line that does not. That list becomes the section's
//       `line_names`, which jsonspec §6.4 makes a hard constraint on the
//       solver — the difference between 東京→品川 drawn on the Tōkaidō
//       Shinkansen and the same pair drawn along the Yamanote loop.
//
//    3. THE RECORD. Everything else is transcription: platforms onto the
//       stops that have them, the service onto `number`, the operator onto
//       `company` in the short form the store already uses.
// =========================================================================

extension TransferGuide {

    public static func lineHints(for leg: Leg) -> [String] {
        var hints: [String] = []
        for service in leg.serviceNames where !service.isEmpty {
            var name = service
            for prefix in ["JR", "Jr", "jr"] where name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
            if let bracket = name.firstIndex(of: "("), bracket != name.startIndex {
                name = String(name[name.startIndex..<bracket])
            }
            guard name.hasSuffix("線") || name.hasSuffix("ライン") else { continue }
            if !hints.contains(name) { hints.append(name) }
        }
        return hints
    }

    // MARK: - what kind of train this is

    /// The `train_type` a service name spells, in the vocabulary the committed
    /// store already uses. `普通` where the service names only a line: a line
    /// name with no class in front of it is a local service.
    public static func trainType(for leg: Leg) -> String {
        // 新幹線 anywhere, because no line but a Shinkansen is spelled with
        // it. Every other class has to LEAD the service name, because that is
        // where Yahoo puts it — and because 北越急行ほくほく線 is a local
        // service on a third-sector railway whose company name happens to
        // contain 急行, which a substring search reads as an express.
        if leg.serviceNames.contains(where: { $0.contains("新幹線") }) { return "新幹線" }
        var service = leg.service
        for prefix in ["JR", "Jr", "jr"] where service.hasPrefix(prefix) {
            service = String(service.dropFirst(prefix.count))
            break
        }
        for word in [
            "寝台特急", "特別快速", "通勤快速", "区間快速", "新快速", "快速急行",
            "区間急行", "特急", "急行", "快速", "準急", "各駅停車", "各停", "普通", "ライナー",
        ] where service.hasPrefix(word) {
            return word == "各駅停車" || word == "各停" ? "普通" : word
        }
        // JR East writes the class after the line: `ＪＲ鹿児島本線快速`. Only
        // where the name also holds 線 — 智頭急行 and 北越急行 end in a class
        // word and are companies, and their trains are ordinary services.
        if service.contains("線") {
            for word in ["特別快速", "通勤快速", "区間快速", "新快速", "快速", "特急", "準急"]
            where service.hasSuffix(word) {
                return word
            }
        }
        return "普通"
    }

    /// Whether this leg runs on a Shinkansen. Read from the service name
    /// rather than from the resolved lines, because it is what decides WHICH
    /// lines are even considered.
    public static func isShinkansen(_ leg: Leg) -> Bool {
        leg.serviceNames.contains { $0.contains("新幹線") }
    }

    // MARK: - building

    public struct BuildOptions: Sendable {
        /// `"YYYY-MM-DD"`, or nil for a record with no date.
        public var date: String?
        /// Which package these rides belong to. Yahoo covers Japan, so this is
        /// `"jp"` in practice and an argument anyway — a hard-coded country in
        /// a builder is the kind of thing that is only found when a second one
        /// arrives.
        public var region: String
        /// The stem of every record id: `yahoo_20260828_01`.
        public var idPrefix: String
        /// Whether these segments count as ridden. False writes a plan: the
        /// route still draws, and the mileage statistics leave it alone until
        /// the reader says the journey happened.
        public var ridden: Bool
        /// Ids already in the store, so a second import of the same day does
        /// not silently take the first one's place.
        public var existingIDs: Set<String>

        public init(
            date: String? = nil, region: String = "jp", idPrefix: String = "yahoo",
            ridden: Bool = true, existingIDs: Set<String> = []
        ) {
            self.date = date
            self.region = region
            self.idPrefix = idPrefix
            self.ridden = ridden
            self.existingIDs = existingIDs
        }
    }

    public struct BuildResult: Sendable {
        public var trains: [Train]
        /// Station names the package had no entry for, in document order and
        /// without repeats. A journey imports with them missing — the record
        /// keeps the name and loses only the code — and the preview says which
        /// ones so the reader can fix them in the editor rather than wonder
        /// why one stretch did not draw.
        public var unresolved: [String]
        public var resolvedCalls: Int
        public var totalCalls: Int

        public init(
            trains: [Train] = [], unresolved: [String] = [], resolvedCalls: Int = 0,
            totalCalls: Int = 0
        ) {
            self.trains = trains
            self.unresolved = unresolved
            self.resolvedCalls = resolvedCalls
            self.totalCalls = totalCalls
        }
    }

    /// Turns the legs of a parsed route into canonical journeys, one per leg.
    ///
    /// One record per leg rather than one per route, because that is what the
    /// schema is: a ``Train`` has one `number`, one `company` and one
    /// `direction`, and the committed multi-leg samples
    /// (`new-year-grand-loop.json`) are already written this way.
    public static func build(
        route: Route, options: BuildOptions, stations: StationIndex
    ) -> BuildResult {
        let legs = route.ridableLegs
        guard !legs.isEmpty else { return BuildResult() }

        // Resolved once across the WHOLE journey, not per leg. A transfer
        // station belongs to two legs, and resolving each leg on its own would
        // let 大宮 be one complex arriving and another leaving.
        var names: [String] = []
        var hints: [[String]] = []
        var spans: [Range<Int>] = []
        for leg in legs {
            let start = names.count
            // 新幹線 as a hint in its own right. A named express gives the
            // resolver no line to prefer, so 広島 was as likely to resolve to
            // the tram stop a hundred metres away as to the station with the
            // Shinkansen platforms — and the section between two tram stops
            // shares no line with anything, so it drew nothing.
            var legHints = lineHints(for: leg)
            if isShinkansen(leg), !legHints.contains("新幹線") { legHints.append("新幹線") }
            for call in leg.calls {
                names.append(call.name)
                hints.append(legHints)
            }
            spans.append(start..<names.count)
        }
        var places = StationIndex.resolve(names: names, hints: hints, index: stations)
        StationIndex.fill(names: names, places: &places, index: stations)

        var unresolved: [String] = []
        for (name, place) in zip(names, places) where place == nil {
            if !unresolved.contains(name) { unresolved.append(name) }
        }

        var used = options.existingIDs
        var trains: [Train] = []
        for (index, leg) in legs.enumerated() {
            let span = spans[index]
            let legPlaces = Array(places[span])
            let id = uniqueID(options: options, ordinal: index + 1, used: &used)
            trains.append(
                train(
                    leg: leg, places: legPlaces, id: id, options: options, stations: stations))
        }

        return BuildResult(
            trains: trains,
            unresolved: unresolved,
            resolvedCalls: places.reduce(0) { $0 + ($1 == nil ? 0 : 1) },
            totalCalls: places.count)
    }

    private static func uniqueID(
        options: BuildOptions, ordinal: Int, used: inout Set<String>
    ) -> String {
        let stamp = (options.date ?? "").filter { $0.isASCII && $0.isNumber }
        let prefix = options.idPrefix.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        let stem = [prefix.isEmpty ? "yahoo" : prefix, stamp.isEmpty ? "undated" : stamp]
            .joined(separator: "_")
        var candidate = String(format: "%@_%02d", stem, ordinal)
        var suffix = 2
        while used.contains(candidate) {
            candidate = String(format: "%@_%02d-%d", stem, ordinal, suffix)
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func train(
        leg: Leg, places: [StationIndex.Place?], id: String, options: BuildOptions,
        stations: StationIndex
    ) -> Train {
        let hints = lineHints(for: leg)
        let shinkansen = isShinkansen(leg)

        var stops: [Stop] = []
        for (index, call) in leg.calls.enumerated() {
            let isFirst = index == 0
            let isLast = index == leg.calls.count - 1
            let stop = Stop(
                name: call.name,
                n02StationCode: places[index]?.code,
                platformNumber: isFirst
                    ? leg.departurePlatform : (isLast ? leg.arrivalPlatform : nil),
                arrival: call.arrival,
                departure: call.departure,
                stopType: isFirst ? "origin" : (isLast ? "destination" : "passenger_stop"),
                rideSegment: options.ridden)
            stops.append(stop)
        }

        var sections: [RouteSection] = []
        var lineNamesSeen: [String] = []
        var operatorsSeen: [String] = []
        var colorHex: String?
        for index in 0..<max(leg.calls.count - 1, 0) {
            let from = places[index]
            let to = places[index + 1]
            let shared = StationIndex.sharedLines(from: from, to: to, shinkansen: shinkansen, hints: hints)
            for line in shared {
                if !lineNamesSeen.contains(line.name) { lineNamesSeen.append(line.name) }
                if let company = line.operatorName, !operatorsSeen.contains(company) {
                    operatorsSeen.append(company)
                }
                if colorHex == nil { colorHex = line.colorHex }
            }
            sections.append(
                RouteSection(
                    from: leg.calls[index].name,
                    to: leg.calls[index + 1].name,
                    fromN02StationCode: from?.code,
                    toN02StationCode: to?.code,
                    lineNames: shared.isEmpty ? nil : shared.map(\.name),
                    operatorNames: shared.compactMap(\.operatorName).isEmpty
                        ? nil : Array(Set(shared.compactMap(\.operatorName))).sorted()))
        }

        // `jr_only` is a constraint, so it takes the strict reading: the
        // service says JR, or every operator the resolved lines named is one.
        // A leg where one end is a JR platform and the other is not would
        // otherwise be solved as if the private half did not exist.
        let isJR = leg.service.hasPrefix("JR")
            || (!operatorsSeen.isEmpty && operatorsSeen.allSatisfy { $0.hasSuffix("旅客鉄道") })
        let policy = RoutePolicy(
            mode: "single_primary_route",
            jrOnly: isJR,
            allowAlternatives: false,
            allowBrowserStraightLineFallback: false,
            allowedInstitutionTypeCodes: StationIndex.institutionCodes(
                shinkansen: shinkansen, isJR: isJR),
            preferredLineNames: lineNamesSeen.isEmpty ? nil : lineNamesSeen,
            preferredOperatorNames: operatorsSeen.isEmpty ? nil : operatorsSeen,
            institutionFilterMode: "soft")

        let origin = leg.calls.first?.name ?? ""
        let destination = leg.calls.last?.name ?? ""
        return Train(
            id: id,
            date: options.date,
            number: number(for: leg),
            trainType: trainType(for: leg),
            company: company(from: operatorsSeen, service: leg.service),
            origin: origin,
            destination: destination,
            direction: leg.destination ?? destination,
            visible: true,
            style: TrainStyle(color: colorHex ?? TrainValidation.defaultTrainColor),
            routePolicy: policy,
            routeSections: sections.isEmpty ? nil : sections,
            stops: stops,
            region: options.region)
    }

    /// The lines both ends of a section carry, narrowed by what the leg is.
    ///
    /// The narrowing is one rule and it does most of the work: a Shinkansen leg
    /// may only be on a line whose name says 新幹線, and every other leg may
    /// only be on a line whose name does not. 東京 and 品川 share five lines,
    /// and that rule leaves exactly the Tōkaidō Shinkansen.
    // MARK: - the year a screenshot does not print


    /// `JR特急北斗8号（10:45 函館行・E5系）` — the house style of the committed
    /// store, which already writes its context this way:
    /// `普通（08:05 我孫子行・東京メトロ千代田線から直通）`.
    ///
    /// The bracket is where the facts the schema has no field for survive.
    /// Rolling stock and a 直通 line change are both properties of the RIDE
    /// rather than of the record, and `number` is free text — so they are
    /// written here rather than added to jsonspec, which the web app also
    /// reads and which this fork does not get to extend for a convenience.
    static func number(for leg: Leg) -> String {
        let service = leg.service.isEmpty ? "乗車" : leg.service
        var inside: [String] = []
        switch (leg.calls.first?.departure, leg.destination) {
        case (let time?, let bound?): inside.append("\(time) \(bound)行")
        case (let time?, nil): inside.append("\(time) 発")
        case (nil, let bound?): inside.append("\(bound)行")
        default: break
        }
        if !leg.throughServices.isEmpty {
            inside.append("\(leg.throughServices.joined(separator: "・"))直通")
        }
        if let equipment = leg.equipment { inside.append(equipment) }
        guard !inside.isEmpty else { return service }
        return "\(service)（\(inside.joined(separator: "・"))）"
    }

    /// `東日本旅客鉄道` as `JR東日本` — the spelling the committed store uses.
    static func company(from operators: [String], service: String) -> String {
        let labels = operators.map { OperatorBranding.companyLabel($0) }.filter { !$0.isEmpty }
        var unique: [String] = []
        for label in labels where !unique.contains(label) { unique.append(label) }
        if !unique.isEmpty { return unique.joined(separator: "/") }
        return service.hasPrefix("JR") ? "JR" : ""
    }

    /// The calendar day `8月28日` means, given when the reader is importing.
    ///
    /// Yahoo prints no year. The nearest reading of the day is taken —
    /// December's screenshot imported in January belongs to last year, and
    /// January's imported in December belongs to next — rather than assuming
    /// the current one, which is wrong for exactly the two weeks of the year
    /// when a mistake is most likely.
    public static func calendarDate(
        month: Int, day: Int, year: Int?, today: (year: Int, month: Int, day: Int)
    ) -> String? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let year { return Dates.format(year: year, month: month, day: day) }
        let todayOrdinal = today.month * 31 + today.day
        let candidateOrdinal = month * 31 + day
        let difference = candidateOrdinal - todayOrdinal
        let resolved =
            difference > 6 * 31 ? today.year - 1 : (difference < -6 * 31 ? today.year + 1 : today.year)
        return Dates.format(year: resolved, month: month, day: day)
    }
}

extension Dates {
    /// `YYYY-MM-DD`, the only spelling a record's `date` takes.
    static func format(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
