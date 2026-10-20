import Foundation

// =========================================================================
//  Train.swift — the itinerary model, and the rules that decide what an
//  itinerary IS.
//
//  Ported from jsonspec.md (schema 1.3), app-validation.js §33 and the
//  app-store-ops.js §18–§19 canonical shapes the validator sits between.
//
//  There are two layers here and keeping them apart is the whole design:
//
//    * ``TrainStore`` / ``Train`` / ``Stop`` / ``RouteSection`` /
//      ``RoutePolicy`` / ``TrainStyle`` are a faithful mirror of the
//      CANONICAL shape — the shape the web app writes. They round-trip both
//      committed stores without loss, and they are strict: a field the
//      canonical writer always emits is non-optional, so a decode failure
//      means "this was not canonical", not "this was invalid".
//
//    * ``TrainValidation`` works on ``TrainValidation/JSON``, an
//      order-preserving dynamic value, because that is the only thing that
//      can represent what the validator actually receives. Half of what
//      makes validateTrain interesting is what it does with a `ride_segment`
//      that is the string "true", a `route_sections` that is the number 0,
//      or a `stops` row that is null — none of which a typed model can hold.
//      The lenient inbound path (``TrainValidation/normalizeImportedTrain``)
//      is what bridges the two: dynamic JSON in, a strict ``Train`` out.
//
//  Every rule below reproduces what the JavaScript does TODAY, including the
//  parts that look accidental. `port-fixtures/validation.json` records the
//  verdicts, and the ones worth knowing about are marked "ACCEPTS:" at the
//  line responsible. They are not bugs to fix here — a port that quietly
//  tightens a rule is a port whose disagreements can no longer be read, and
//  it would start rejecting itineraries the committed archive contains.
// =========================================================================

// MARK: - the canonical model

/// Whether the reader has confirmed the physical railway used by this ride.
/// An absent value preserves the solving behavior of legacy archives.
public enum RouteConfirmation: String, Codable, Equatable, Sendable {
    case pending
    case confirmed
}

/// `{ "schema_version": "1.3", "trains": [...] }` — jsonspec §2.1.
///
/// The top level is an object and never an array, and it carries exactly
/// these two keys: jsonspec §2.3 rule 4 notes that 1.3 deliberately did *not*
/// add a `country` field, because the strict whitelist is what keeps an older
/// Japanese store loadable. Country comes from the active rail package.
public struct TrainStore: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var trains: [Train]

    public init(schemaVersion: String = TrainValidation.schemaVersion, trains: [Train] = []) {
        self.schemaVersion = schemaVersion
        self.trains = trains
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case trains
    }
}

/// One ridden itinerary — jsonspec §3.1.
///
/// ## What is optional, and why it is not obvious
///
/// `id`, `number`, `origin`, `destination` and `stops` are non-optional
/// because the export path always writes them and the validator always
/// requires them. Everything else is optional, and each for its own reason
/// rather than as a blanket policy:
///
///   - `date` may be genuinely absent: jsonspec §3.3 lets the date be
///     inferred from the id, and `validateTrain` accepts an absent `date`
///     while *rejecting* an explicit `null` one. Absent and null are
///     therefore not the same thing, which is why this is `String?` encoded
///     only when present rather than always written as null.
///   - `trainType`, `vehicleType`, `company`, `direction`, `visible`, `style`,
///     `routePolicy`, `routeSections` are all "filled with a default on
///     import, always written on export" (§3.1). The committed stores carry
///     every one of them, so the optionality here is about representing a
///     hand-authored file faithfully, not about the app's own output.
///
/// `direction` is a plain `String` and not an enum on purpose. jsonspec §3.1
/// *recommends* `up` / `down` / `unknown` and nothing validates it — the
/// committed Japanese store puts destination station names in it
/// (`"和光市・池袋"`, `"内回り"`), so an enum would reject 117 of the 201
/// real itineraries.
public struct Train: Codable, Equatable, Sendable {
    public var id: String
    public var date: String?
    public var number: String
    /// The service's Latin name — 「Nemuro Main Line Local」 under 「根室本線
    /// 普通 (5625D)」 — jsonspec §3.1's `number_en`. Optional and written
    /// only when set: the committed stores never had one, and a file that
    /// never had one round-trips unchanged. Stores that carried the name
    /// inside the caption — 「根室本線 普通 (Nemuro Main Line Local) (5625D)」
    /// — are split into the two fields on import; see ``ServiceCaption``.
    public var numberEn: String?
    public var trainType: String?
    /// Rolling-stock model or vehicle type, distinct from `trainType`, which
    /// describes the passenger service class (for example, limited express).
    /// Optional so existing stores keep their original shape.
    public var vehicleType: String?
    public var company: String?
    /// Registry operator, `op:<region>:<seq>` (ADR 0013). Optional, and written
    /// only when set, so a store that never had one stays byte-identical.
    /// `company` is still written unchanged.
    public var operatorID: String?
    /// Ordered operators for a slash-joined company. Written only when set.
    /// A single company keeps `operatorID` and leaves this absent.
    public var operatorIDs: [String]?
    public var origin: String
    public var destination: String
    /// Recommended `up` / `down` / `unknown`, but free text in practice — see
    /// the type's documentation.
    public var direction: String?
    public var visible: Bool?
    public var style: TrainStyle?
    public var routePolicy: RoutePolicy?
    public var routeSections: [RouteSection]?
    /// Pending rides retain their recorded calls and hints, but those hints
    /// must not produce a drawn railway or precise mileage until confirmed.
    public var routeConfirmation: RouteConfirmation?
    public var requiresRouteConfirmation: Bool { routeConfirmation == .pending }
    public var stops: [Stop]
    /// Which regional package this itinerary belongs to — `"jp"`, `"tw"`,
    /// `"hk"`, `"mo"` or `"kr"`.
    ///
    /// Also preserved by the web import/export path. The web app
    /// keeps one store per region and answers this question by asking which
    /// region is switched on; this app draws every region at once, so the
    /// question has to be answered per itinerary instead — the solver, the
    /// mileage statistics and the route cache each need to know which package
    /// a ride is measured against.
    ///
    /// Safe to add to the canonical file: `validateTrainStore` in
    /// app-validation.js applies `assertOnlyKeys` to the store ROOT only, and
    /// `validateTrain` checks the fields it knows without rejecting others, so
    /// a store written here still imports into the web app. Optional, and
    /// written only when set, so a file that never had one round-trips
    /// unchanged — and ``RegionCatalog`` can re-derive it from the stops when
    /// it is missing.
    public var region: String?
    /// User remarks or sourced service notes, carried through import and export.
    public var notes: String?
    /// Optional user grouping, shared across regions and preserved in archives.
    public var journeyGroup: JourneyGroup?

    public init(
        id: String,
        date: String? = nil,
        number: String,
        numberEn: String? = nil,
        trainType: String? = nil,
        vehicleType: String? = nil,
        company: String? = nil,
        origin: String,
        destination: String,
        direction: String? = nil,
        visible: Bool? = nil,
        style: TrainStyle? = nil,
        routePolicy: RoutePolicy? = nil,
        routeSections: [RouteSection]? = nil,
        stops: [Stop],
        region: String? = nil,
        notes: String? = nil,
        journeyGroup: JourneyGroup? = nil,
        routeConfirmation: RouteConfirmation? = nil,
        operatorID: String? = nil,
        operatorIDs: [String]? = nil
    ) {
        self.id = id
        self.date = date
        self.number = number
        self.numberEn = numberEn
        self.trainType = trainType
        self.vehicleType = vehicleType
        self.company = company
        self.origin = origin
        self.destination = destination
        self.direction = direction
        self.visible = visible
        self.style = style
        self.routePolicy = routePolicy
        self.routeSections = routeSections
        self.stops = stops
        self.region = region
        self.notes = notes
        self.journeyGroup = journeyGroup
        self.routeConfirmation = routeConfirmation
        self.operatorID = operatorID
        self.operatorIDs = operatorIDs.flatMap { $0.isEmpty ? nil : $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, number, origin, destination, direction, visible, style, stops
        case numberEn = "number_en"
        case trainType = "train_type"
        case vehicleType = "vehicle_type"
        case company
        case operatorID = "operator_id"
        case operatorIDs = "operator_ids"
        case routePolicy = "route_policy"
        case routeSections = "route_sections"
        case region, notes
        case journeyGroup = "journey_group"
        case routeConfirmation = "route_confirmation"
    }

    // Written out only when present, so that a store which omits a field
    // round-trips as one that omits it. Swift's synthesised encoder already
    // does this for `Optional` stored properties — it calls
    // `encodeIfPresent`, not `encode` — so that is not why this encoder is
    // hand-written. It exists to pin the emitted key order to jsonspec's,
    // independent of the struct's stored-property order: synthesis follows
    // declaration order, and a future reordering of these properties would
    // silently reorder the JSON and produce diff noise across the 201
    // committed itineraries with no compiler warning to catch it.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encode(number, forKey: .number)
        try container.encodeIfPresent(numberEn, forKey: .numberEn)
        try container.encodeIfPresent(trainType, forKey: .trainType)
        try container.encodeIfPresent(vehicleType, forKey: .vehicleType)
        try container.encodeIfPresent(company, forKey: .company)
        try container.encodeIfPresent(operatorID, forKey: .operatorID)
        try container.encodeIfPresent(operatorIDs, forKey: .operatorIDs)
        try container.encode(origin, forKey: .origin)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(visible, forKey: .visible)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(routePolicy, forKey: .routePolicy)
        try container.encodeIfPresent(routeSections, forKey: .routeSections)
        try container.encode(stops, forKey: .stops)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(journeyGroup, forKey: .journeyGroup)
        try container.encodeIfPresent(routeConfirmation, forKey: .routeConfirmation)
    }
}

/// One station on the itinerary — jsonspec §7.1.
///
/// A canonical stop encodes its seven base fields, `null` included. The
/// optional actual-time fields are written only when recorded, so old stores
/// retain their original shape. The bundled 1.3 archives predate
/// `platform_number`, so direct decode→encode preserves that one legacy
/// absence; every import, edit, or canonical export creates a stop with the
/// field present and writes an unknown value as explicit null.
///
/// `name`, `stopType` and `rideSegment` are non-optional for the same reason
/// — the canonical writer never leaves them out or null. A lean hand-written
/// stop (`{"name": "東京"}`) is legal *input*, and it reaches this type
/// through ``TrainValidation/normalizeImportedStop(_:)``, which applies the
/// §7.1 defaults. It is not decodable as a `Stop` directly, and that
/// asymmetry is deliberate: decoding is for canonical data, importing is for
/// everything else.
public struct Stop: Codable, Equatable, Sendable {
    /// Identity of this visit, independent of the physical station. Absent
    /// metadata denotes an authored legacy visit.
    public struct RouteEditingMetadata: Codable, Equatable, Sendable {
        public var visitID: UUID
        public var generatedBy: String?

        public init(visitID: UUID = UUID(), generatedBy: String? = nil) {
            self.visitID = visitID
            self.generatedBy = generatedBy
        }

        private enum CodingKeys: String, CodingKey {
            case visitID = "visit_id"
            case generatedBy = "generated_by"
        }
    }

    public var routeEditing: RouteEditingMetadata?
    public var name: String
    /// The official station code of the current country's rail data source —
    /// a six-digit Japanese `N02_005c`, a TDX-style `StationUID`, or nil.
    /// The key name is historical (jsonspec §2.3): the value has not been
    /// N02-only since Taiwan was added.
    public var n02StationCode: String?
    /// Company station, `st:<region>:<seq>` (ADR 0013). Optional, and written
    /// only when set. `n02_station_code` stays the external code.
    public var stationID: String?
    /// Passenger-facing platform/track number. `0` is valid; negative and
    /// fractional values are rejected. `nil` serializes as JSON `null` and is
    /// never rendered as the word "null".
    public var platformNumber: Int? {
        didSet { hasPlatformNumberField = true }
    }
    /// Distinguishes a legacy absent field from an explicit JSON null for
    /// lossless archive reads. It is intentionally not part of semantic
    /// equality: both spell the same unknown platform.
    var hasPlatformNumberField: Bool
    /// `"HH:MM"`, where hours run past 24 to spell the next day (§10.5:
    /// `25:10` is 01:10 tomorrow). Nothing validates the format — see
    /// ``TrainValidation/validateTrain(_:index:ids:)``.
    public var arrival: String?
    /// Manually recorded observed arrival. Kept separate from the scheduled
    /// value so clients can show the signed early/late difference.
    public var actualArrival: String?
    public var departure: String?
    /// Manually recorded observed departure. See ``actualArrival``.
    public var actualDeparture: String?
    /// One of ``TrainValidation/stopTypes`` (§7.2).
    public var stopType: String
    public var rideSegment: Bool

    public init(
        name: String,
        n02StationCode: String? = nil,
        platformNumber: Int? = nil,
        arrival: String? = nil,
        actualArrival: String? = nil,
        departure: String? = nil,
        actualDeparture: String? = nil,
        stopType: String = "passenger_stop",
        rideSegment: Bool = false,
        routeEditing: RouteEditingMetadata? = nil,
        stationID: String? = nil
    ) {
        self.name = name
        self.n02StationCode = n02StationCode
        self.platformNumber = platformNumber
        self.hasPlatformNumberField = true
        self.arrival = arrival
        self.actualArrival = actualArrival
        self.departure = departure
        self.actualDeparture = actualDeparture
        self.stopType = stopType
        self.rideSegment = rideSegment
        self.routeEditing = routeEditing
        self.stationID = stationID
    }

    private enum CodingKeys: String, CodingKey {
        case name, platformNumber = "platform_number", arrival, departure
        case actualArrival = "actual_arrival"
        case actualDeparture = "actual_departure"
        case n02StationCode = "n02_station_code"
        case stationID = "station_id"
        case stopType = "stop_type"
        case rideSegment = "ride_segment"
        case routeEditing = "route_editing"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // ADR 0010: persisted rides may carry a legacy HK/MO code.
        n02StationCode = try container.decodeIfPresent(String.self, forKey: .n02StationCode)
            .map(StationCodeAliases.canonical)
        stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
        hasPlatformNumberField = container.contains(.platformNumber)
        platformNumber = try container.decodeIfPresent(Int.self, forKey: .platformNumber)
        arrival = try container.decodeIfPresent(String.self, forKey: .arrival)
        actualArrival = try container.decodeIfPresent(String.self, forKey: .actualArrival)
        departure = try container.decodeIfPresent(String.self, forKey: .departure)
        actualDeparture = try container.decodeIfPresent(String.self, forKey: .actualDeparture)
        stopType = try container.decode(String.self, forKey: .stopType)
        rideSegment = try container.decode(Bool.self, forKey: .rideSegment)
        routeEditing = try container.decodeIfPresent(RouteEditingMetadata.self, forKey: .routeEditing)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(n02StationCode, forKey: .n02StationCode)  // null, not absent
        try container.encodeIfPresent(stationID, forKey: .stationID)
        if hasPlatformNumberField {
            try container.encode(platformNumber, forKey: .platformNumber)  // null, not absent
        }
        try container.encode(arrival, forKey: .arrival)
        try container.encodeIfPresent(actualArrival, forKey: .actualArrival)
        try container.encode(departure, forKey: .departure)
        try container.encodeIfPresent(actualDeparture, forKey: .actualDeparture)
        try container.encode(stopType, forKey: .stopType)
        try container.encode(rideSegment, forKey: .rideSegment)
        try container.encodeIfPresent(routeEditing, forKey: .routeEditing)
    }

    public static func == (lhs: Stop, rhs: Stop) -> Bool {
        lhs.name == rhs.name
            && lhs.n02StationCode == rhs.n02StationCode
            && lhs.stationID == rhs.stationID
            && lhs.platformNumber == rhs.platformNumber
            && lhs.arrival == rhs.arrival
            && lhs.actualArrival == rhs.actualArrival
            && lhs.departure == rhs.departure
            && lhs.actualDeparture == rhs.actualDeparture
            && lhs.stopType == rhs.stopType
            && lhs.rideSegment == rhs.rideSegment
            && lhs.routeEditing == rhs.routeEditing
    }
}

/// One physically adjacent stop pair and the hard constraints on solving it —
/// jsonspec §6.1 and §6.1b.
///
/// The two codes are encoded every time (null included) and everything else
/// only when present, which is exactly what `leanExportSection` writes: the
/// endpoint names are dropped when the station table can reconstruct them
/// from the codes (§13.4), and the line/operator hints and the branch
/// number/name are dropped when empty. 1 861 of the 2 303 sections in the
/// committed Japanese store carry no `from`/`to` at all.
public struct RouteSection: Codable, Hashable, Sendable {
    public var from: String?
    public var to: String?
    public var fromN02StationCode: String?
    public var toN02StationCode: String?
    /// Company station that owns `fromN02StationCode`. Absent until upgrade.
    public var fromStationID: String?
    /// Company station that owns `toN02StationCode`. Absent until upgrade.
    public var toStationID: String?
    /// A **hard** constraint on which line the solver may traverse (§6.4).
    /// Empty or absent means unconstrained, which is a branch-leak risk at a
    /// junction rather than a neutral default.
    public var lineNames: [String]?
    public var operatorNames: [String]?
    /// Stable package line identities and ordered physical interval identities.
    public var lineIDs: [String]?
    public var sectionCodes: [String]?
    public var sectionCodesOrigin: RecordedRouteAdmission.SectionCodesOrigin?
    /// A branch portion run under a different 号 — はやぶさ↔こまち (§6.1b).
    public var number: String?
    public var name: String?

    public init(
        from: String? = nil,
        to: String? = nil,
        fromN02StationCode: String? = nil,
        toN02StationCode: String? = nil,
        fromStationID: String? = nil,
        toStationID: String? = nil,
        lineNames: [String]? = nil,
        operatorNames: [String]? = nil,
        lineIDs: [String]? = nil,
        sectionCodes: [String]? = nil,
        sectionCodesOrigin: RecordedRouteAdmission.SectionCodesOrigin? = nil,
        number: String? = nil,
        name: String? = nil
    ) {
        self.from = from
        self.to = to
        self.fromN02StationCode = fromN02StationCode
        self.toN02StationCode = toN02StationCode
        self.fromStationID = fromStationID
        self.toStationID = toStationID
        self.lineNames = lineNames
        self.operatorNames = operatorNames
        self.lineIDs = lineIDs
        self.sectionCodes = sectionCodes
        self.sectionCodesOrigin = sectionCodesOrigin
        self.number = number
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case from, to, number, name
        case fromN02StationCode = "from_n02_station_code"
        case toN02StationCode = "to_n02_station_code"
        case fromStationID = "from_station_id"
        case toStationID = "to_station_id"
        case lineNames = "line_names"
        case operatorNames = "operator_names"
        case lineIDs = "line_ids"
        case sectionCodes = "section_codes"
        case sectionCodesOrigin = "section_codes_origin"
    }

    /// Station codes are canonicalised on decode (ADR 0010), so a stored
    /// legacy HK/MO code never reaches routing or matching.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        fromN02StationCode = try container.decodeIfPresent(
            String.self, forKey: .fromN02StationCode
        ).map(StationCodeAliases.canonical)
        toN02StationCode = try container.decodeIfPresent(
            String.self, forKey: .toN02StationCode
        ).map(StationCodeAliases.canonical)
        fromStationID = try container.decodeIfPresent(String.self, forKey: .fromStationID)
        toStationID = try container.decodeIfPresent(String.self, forKey: .toStationID)
        lineNames = try container.decodeIfPresent([String].self, forKey: .lineNames)
        operatorNames = try container.decodeIfPresent([String].self, forKey: .operatorNames)
        lineIDs = try container.decodeIfPresent([String].self, forKey: .lineIDs)
        sectionCodes = try container.decodeIfPresent([String].self, forKey: .sectionCodes)
        sectionCodesOrigin = try container.decodeIfPresent(RecordedRouteAdmission.SectionCodesOrigin.self, forKey: .sectionCodesOrigin)
        number = try container.decodeIfPresent(String.self, forKey: .number)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encode(fromN02StationCode, forKey: .fromN02StationCode)  // null, not absent
        try container.encode(toN02StationCode, forKey: .toN02StationCode)
        try container.encodeIfPresent(fromStationID, forKey: .fromStationID)
        try container.encodeIfPresent(toStationID, forKey: .toStationID)
        try container.encodeIfPresent(lineNames, forKey: .lineNames)
        try container.encodeIfPresent(operatorNames, forKey: .operatorNames)
        try container.encodeIfPresent(lineIDs, forKey: .lineIDs)
        try container.encodeIfPresent(sectionCodes, forKey: .sectionCodes)
        try container.encodeIfPresent(sectionCodesOrigin, forKey: .sectionCodesOrigin)
        try container.encodeIfPresent(number, forKey: .number)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

/// How this train's route may be solved — jsonspec §5.1.
///
/// Every field is optional even though `canonicalRoutePolicy` fills them all
/// in, because 46 of the 201 policies in the committed Japanese store predate
/// the current writer and carry no `preferred_line_names` /
/// `preferred_operator_names`. Encoding those as `null` would rewrite the
/// archive on the first save.
///
/// Note that `jrOnly` is advisory: jsonspec §17 rule 14 says the solver never
/// reads it. `allowedInstitutionTypeCodes` is what actually narrows the
/// search, and only in Japan — §17 rule 17 says Taiwan's packages carry no
/// N02_002 at all, so the array is kept for canonical shape and ignored.
public struct RoutePolicy: Codable, Equatable, Sendable {
    /// Must be `"single_primary_route"`; nothing else validates.
    public var mode: String?
    public var jrOnly: Bool?
    /// Must be `false`.
    public var allowAlternatives: Bool?
    /// Must be `false`. jsonspec §13.5 / §17 rule 11: drawing a straight line
    /// between two stations is forbidden under all circumstances.
    public var allowBrowserStraightLineFallback: Bool?
    /// N02_002 事業者種別: 1 = JR 新幹線, 2 = JR 在来線, 3 = 公営鉄道,
    /// 4 = 民営鉄道, 5 = 第三セクター.
    public var allowedInstitutionTypeCodes: [String]?
    /// Soft bias, not a constraint (§5.3) — a deviation is penalised in
    /// proportion to distance, never forbidden.
    public var preferredLineNames: [String]?
    public var preferredOperatorNames: [String]?
    /// `"soft"` or `"hard"` (§5.4).
    public var institutionFilterMode: String?

    public init(
        mode: String? = nil,
        jrOnly: Bool? = nil,
        allowAlternatives: Bool? = nil,
        allowBrowserStraightLineFallback: Bool? = nil,
        allowedInstitutionTypeCodes: [String]? = nil,
        preferredLineNames: [String]? = nil,
        preferredOperatorNames: [String]? = nil,
        institutionFilterMode: String? = nil
    ) {
        self.mode = mode
        self.jrOnly = jrOnly
        self.allowAlternatives = allowAlternatives
        self.allowBrowserStraightLineFallback = allowBrowserStraightLineFallback
        self.allowedInstitutionTypeCodes = allowedInstitutionTypeCodes
        self.preferredLineNames = preferredLineNames
        self.preferredOperatorNames = preferredOperatorNames
        self.institutionFilterMode = institutionFilterMode
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case jrOnly = "jr_only"
        case allowAlternatives = "allow_alternatives"
        case allowBrowserStraightLineFallback = "allow_browser_straight_line_fallback"
        case allowedInstitutionTypeCodes = "allowed_institution_type_codes"
        case preferredLineNames = "preferred_line_names"
        case preferredOperatorNames = "preferred_operator_names"
        case institutionFilterMode = "institution_filter_mode"
    }
}

/// The one per-train display value that survives — jsonspec §4.1.
///
/// `weight` and `unridden_opacity` were removed from the schema: line width
/// is a global setting and unridden intervals are hidden outright rather than
/// faded, so both are dropped on the way out by
/// ``TrainValidation/canonicalStyle(_:)``. They are not represented here at
/// all, which is what "dropped" means.
public struct TrainStyle: Codable, Equatable, Sendable {
    /// `#RRGGBB`. The only shape ``TrainValidation/isValidTrainColor(_:)``
    /// accepts.
    public var color: String?

    public init(color: String? = nil) { self.color = color }
}

// MARK: - the rules

/// `app-validation.js` §33 and the `app-store-ops.js` §18–§19 shapes.
///
/// ## What this accepts that it arguably should not
///
/// Reproduced deliberately; each is marked "ACCEPTS:" at the responsible
/// line and recorded in `port-fixtures/validation.json`.
///
///   - **A time is never parsed.** `arrival` and `departure` are only checked
///     to be a string or null, so `"banana"`, `"25:99"` and the legacy
///     `"10:00+1"` all validate. jsonspec §10 states a format; nothing
///     enforces it.
///   - **No two stops are ever compared.** An itinerary whose clock runs
///     backwards is valid.
///   - **`visible` is not type-checked** (jsonspec §15.2 says so outright).
///   - **A falsy-but-present `route_sections` or `route_policy` skips its
///     whole block.** `route_sections: 0` is not an error, it is an unchecked
///     section list.
///   - **`x || []` turns a null array into an empty one**, so a null
///     `line_names` or `allowed_institution_type_codes` passes.
///   - **A JSON number can be a station code.** `stationCodeSystem` coerces
///     with `String(code)` first, so `123456` is a valid `N02_005c`.
///   - **Nothing checks that any stop is ridden** (jsonspec §8.6.4): a train
///     with every `ride_segment` false validates, exports, and draws nothing.
///   - **A null row in `stops` crashes rather than rejects** — see
///     ``validateTrain(_:index:ids:)``.
///
/// ## Why there is not a single `NSRegularExpression` in here
///
/// The JavaScript spells four of these rules as regular expressions, and an
/// ICU translation of the same pattern text answers differently on real
/// input:
///
///   - ICU's `$` matches before a final line terminator; JavaScript's `$`
///     without `/m` matches only at the very end. So `"odr_001\n"` is a valid
///     train id under ICU and is rejected by the app.
///   - ICU's `\d` is `\p{Nd}`, which matches fullwidth and Arabic-Indic
///     digits. `"００３７７０"` would be a valid six-digit N02 station code.
///
/// Both are reachable from CJK data, so every matcher below is a hand-written
/// scan over UTF-16 code units.
public enum TrainValidation {

    // MARK: - constants

    /// `SCHEMA_VERSION` — the version this app writes.
    public static let schemaVersion = "1.3"

    /// `ACCEPTED_SCHEMA_VERSIONS` — the versions it will read.
    public static let acceptedSchemaVersions = ["1.3"]

    /// The five `stop_type` values of jsonspec §7.2, in the order the
    /// editor's `<select>` lists them (running order, not the spec's table
    /// order). The order is contractual because it is joined into the error
    /// message when a value is rejected.
    public static let stopTypes = [
        "origin", "passenger_stop", "pass_through", "operational_stop", "destination",
    ]

    /// `UNDATED` — the bucket for a train whose date could not be determined.
    /// Same value as ``Dates/undated``, which owns the date rules.
    public static let undated = Dates.undated

    /// `TRAIN_ID_PATTERN.source`, quoted verbatim into the error message.
    public static let trainIDPatternSource = "^[a-zA-Z0-9_-]+$"

    /// ADR 0013 company-station id. Quoted into the rejection, same way as
    /// ``trainIDPatternSource``.
    public static let stationIDPatternSource = "^st:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$"

    /// ADR 0013 operator id. Quoted into the rejection.
    public static let operatorIDPatternSource = "^op:(jp|tw|hk|mo|kr|cn):[1-9][0-9]*$"

    public static let defaultTrainColor = "#d9364f"

    /// N02_002 事業者種別 — 1 JR 新幹線, 2 JR 在来線, 3 公営鉄道,
    /// 4 民営鉄道, 5 第三セクター.
    public static let defaultAllowedInstitutionTypeCodes = ["1", "2", "3", "4", "5"]

    // MARK: - errors

    /// A throw out of the validator.
    ///
    /// `kind` is what separates a deliberate rejection from a crash. There is
    /// exactly one input shape that produces the latter, and collapsing the
    /// two would let a port that throws for the right reason look identical
    /// to one that reproduced the bug.
    public struct ValidationError: Error, Equatable, CustomStringConvertible {
        public enum Kind: String, Sendable, Equatable {
            /// `new Error(...)` — a schema rejection with a contractual message.
            case error = "Error"
            /// A `TypeError` the JavaScript did not intend to raise. The
            /// message is V8's own wording and is not a contract; only the
            /// kind is.
            case typeError = "TypeError"
            /// `JSON.parse` failed. Message likewise not contractual.
            case syntaxError = "SyntaxError"
        }

        public let kind: Kind
        public let message: String
        /// Field path of a schema rejection, such as `stops[0].stop_type`.
        /// Absent for a crash, a parse failure, or an unwrapped region message.
        public let path: String?
        /// The reason without the `Train N` prefix. Same absence rules as `path`.
        public let reason: String?

        public init(
            kind: Kind = .error, message: String, path: String? = nil, reason: String? = nil
        ) {
            self.kind = kind
            self.message = message
            self.path = path
            self.reason = reason
        }

        public var description: String { message }
    }

    private static func fail(_ message: String) -> ValidationError {
        ValidationError(kind: .error, message: message)
    }

    /// One schema fact about a record: where it is, and the sentence the
    /// fixture pins. `location` is the text between the train number and the
    /// colon (`""`, `" stop N"`, `" route section N"`).
    public struct Diagnostic: Equatable, Sendable {
        public var path: String
        public var reason: String
        public var location: String

        public init(path: String, reason: String, location: String = "") {
            self.path = path
            self.reason = reason
            self.location = location
        }
    }

    private static func wrapped(_ diagnostic: Diagnostic, index: Int) -> ValidationError {
        ValidationError(
            kind: .error,
            message: "Train \(index + 1)\(diagnostic.location): \(diagnostic.reason)",
            path: diagnostic.path,
            reason: diagnostic.reason)
    }

    private static func throwFirst(_ diagnostics: [Diagnostic], index: Int) throws {
        guard let first = diagnostics.first else { return }
        // Region and railway-identity failures are not train-field errors.
        // Their message has no `Train N` prefix.
        if first.path == "region" { throw fail(first.reason) }
        throw wrapped(first, index: index)
    }

    // MARK: - JavaScript primitives

    /// ECMAScript `WhiteSpace` ∪ `LineTerminator`, which is what
    /// `String.prototype.trim` removes.
    ///
    /// ECMAScript `String.prototype.trim`.
    ///
    /// The rule and its whitespace set moved to ``JSString`` when the parallel
    /// ports landed — this file and `Dates.swift` spelled the same set twice,
    /// and the note that used to be here asked for exactly that move. The name
    /// stays because `StoreOperations` calls it by it.
    static func jsTrim(_ text: String) -> String { JSString.trim(text) }

    /// JavaScript's `===` between two strings.
    ///
    /// JavaScript compares strings by UTF-16 code unit; Swift's `==` compares
    /// by canonical equivalence, so `"が"` written as U+304C and as
    /// U+304B U+3099 are equal in Swift and not in JavaScript. Station names
    /// here are CJK and *are* compared — `leanExportSection` decides whether
    /// to keep a section's endpoint name by comparing it to the station
    /// table's, and `routeSectionMatchesStopPair` matches a section to a stop
    /// pair by name. Both committed stores happen to be entirely NFC today,
    /// so this changes no current answer; it is here so that the first
    /// decomposed name to arrive does not silently change one.
    static func jsStringEquals(_ a: String, _ b: String) -> Bool {
        sameCodeUnits(a, b)
    }

    private static func isASCIIDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    private static func isASCIIUpper(_ unit: UInt16) -> Bool { unit >= 65 && unit <= 90 }
    private static func isASCIILower(_ unit: UInt16) -> Bool { unit >= 97 && unit <= 122 }
    private static func isASCIIAlnum(_ unit: UInt16) -> Bool {
        isASCIIDigit(unit) || isASCIIUpper(unit) || isASCIILower(unit)
    }
    private static func isASCIIHex(_ unit: UInt16) -> Bool {
        isASCIIDigit(unit) || (unit >= 65 && unit <= 70) || (unit >= 97 && unit <= 102)
    }

    // MARK: - predicates

    /// `TRAIN_ID_PATTERN` — `^[a-zA-Z0-9_-]+$`, jsonspec §3.2.
    ///
    /// Train ids flow into `route_id`, route cache keys and DOM ids, which is
    /// why the charset is closed rather than "any non-empty text".
    public static func matchesTrainIDPattern(_ value: String) -> Bool {
        let units = Array(value.utf16)
        guard !units.isEmpty else { return false }
        // `$` anchors at the very end of the input, so a trailing newline is
        // part of the string being matched and fails. See the type's notes.
        return units.allSatisfy { isASCIIAlnum($0) || $0 == 95 /* _ */ || $0 == 45 /* - */ }
    }

    /// `isValidTrainColor` — `^#[0-9a-fA-F]{6}$`, jsonspec §5.1.
    public static func isValidTrainColor(_ value: String?) -> Bool {
        // The JavaScript tests `value || ""`, so null and "" both fail here
        // rather than throwing.
        let units = Array((value ?? "").utf16)
        guard units.count == 7, units[0] == 35 /* # */ else { return false }
        return units[1...].allSatisfy(isASCIIHex)
    }

    /// Which official code system a station code belongs to, or nil.
    ///
    /// jsonspec §2.3: `N02` is Japan's six-digit `N02_005c`; `TDX` is the
    /// hyphenated form used by Taiwan (`TRA-1000`), Hong Kong
    /// (`TML-MTR-WKS`), Macao and Korea. The value is coerced with
    /// `String(code)` and trimmed first, which is where two of the fixture's
    /// surprises come from — a JSON *number* can be a valid code, and a
    /// leading U+FEFF is trimmed away while a leading U+0085 is not.
    public static func stationCodeSystem(_ code: JSON?) -> String? {
        let value = jsTrim(jsToString(code ?? .null))
        let units = Array(value.utf16)

        // ^\d{6}$ — ASCII digits only, because JavaScript's \d has no /u flag.
        if units.count == 6 && units.allSatisfy(isASCIIDigit) { return "N02" }

        // Urban station identities sourced from an OSM marker node.
        if value.hasPrefix("CN-OSM-N"), units.count > 8,
           units.dropFirst(8).allSatisfy({ (48...57).contains($0) }) { return "CN-OSM" }

        // China's official three-letter 12306 station telegraph code.
        if value.hasPrefix("CN-12306-"), units.count == 12,
           units.suffix(3).allSatisfy({ (65...90).contains($0) }) { return "CN-12306" }

        // ^[A-Z][A-Z0-9]*-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$
        // Split on "-": the head may not contain one, and every tail segment
        // must be non-empty, so an empty segment anywhere fails — which is
        // what rejects "A-", "A--1" and "A-1-".
        let segments = units.split(separator: 45, omittingEmptySubsequences: false)
        if segments.count >= 2,
            let head = segments.first, head.count >= 1,
            isASCIIUpper(head[head.startIndex]),
            head.dropFirst().allSatisfy({ isASCIIUpper($0) || isASCIIDigit($0) }),
            segments.dropFirst().allSatisfy({ !$0.isEmpty && $0.allSatisfy(isASCIIAlnum) })
        {
            return "TDX"
        }
        return nil
    }

    /// Convenience for a code already known to be a string.
    public static func stationCodeSystem(_ code: String?) -> String? {
        stationCodeSystem(code.map(JSON.string) ?? JSON.null)
    }

    /// `isValidSourceStationCode` — null, absent, or a recognised system.
    ///
    /// Note that the empty string is *not* valid: it coerces to no system.
    /// jsonspec §2.3 rule 1 says to write `null` when there is no code.
    public static func isValidSourceStationCode(_ code: JSON?) -> Bool {
        guard let code, code != .null else { return true }
        return stationCodeSystem(code) != nil
    }

    /// `platform_number` — absent/null, zero, or a positive JSON integer.
    /// Booleans and numeric strings are not integers in JSON and are rejected.
    public static func isValidPlatformNumber(_ value: JSON?) -> Bool {
        guard let value, value != .null else { return true }
        guard case .number(let number) = value,
              number.isFinite,
              number >= 0,
              number.rounded(.towardZero) == number,
              // `Double(Int.max)` rounds up to 2^63 on 64-bit platforms, so
              // equality is already outside Int's representable range.
              number < Double(Int.max)
        else { return false }
        return true
    }

    /// Reject retired regions before import, storage, or route construction.
    /// Untagged records remain valid only when their station/section identities
    /// do not name a region that this application no longer supports.
    public static func validateSupportedRegions(_ train: JSON) throws {
        if let region = train["region"]?.stringOrNilIfFalsy,
           !["jp", "tw", "hk", "mo", "kr", "cn"].contains(region.lowercased()) {
            throw fail("Unsupported journey region: \(region).")
        }
        func inspect(_ value: JSON) throws {
            switch value {
            case .string(let text):
                let code = text.lowercased()
                if code.hasPrefix("us-") || code.hasPrefix("ca-") {
                    throw fail("Unsupported railway identity: \(text).")
                }
            case .array(let values):
                for item in values { try inspect(item) }
            case .object(let values):
                for key in values.keys where key != "name" && key != "number"
                    && key != "number_en" && key != "notes" && key != "company"
                    && key != "origin" && key != "destination" && key != "id" {
                    if let item = values[key] { try inspect(item) }
                }
            default: break
            }
        }
        try inspect(train)
    }

    public static func validateSupportedRegions(_ train: Train) throws {
        if let region = train.region,
           !["jp", "tw", "hk", "mo", "kr", "cn"].contains(region.lowercased()) {
            throw fail("Unsupported journey region: \(region).")
        }
        func check(_ identity: String?) throws {
            guard let identity else { return }
            let code = identity.lowercased()
            if code.hasPrefix("us-") || code.hasPrefix("ca-") {
                throw fail("Unsupported railway identity: \(identity).")
            }
        }
        for stop in train.stops { try check(stop.n02StationCode) }
        for section in train.routeSections ?? [] {
            try check(section.fromN02StationCode)
            try check(section.toN02StationCode)
            for identity in (section.lineIDs ?? []) + (section.sectionCodes ?? []) {
                try check(identity)
            }
        }
    }

    // MARK: - assertOnlyKeys

    /// `assertOnlyKeys` — the strict inbound whitelist of §19.
    ///
    /// It throws on the **first** offending key in `Object.keys` order, so
    /// which key the message names depends on key order, and JavaScript's key
    /// order is not document order: integer-index keys come first in ascending
    /// *numeric* order, then every other key in insertion order. That rule
    /// lives in ``JSON/Object``, which is why this can just walk `keys`.
    ///
    /// A nil object is not an error — the JavaScript reads
    /// `Object.keys(object || {})`, so null and undefined both pass.
    public static func assertOnlyKeys(
        _ object: JSON?, _ allowedKeys: [String], _ label: String
    ) throws {
        guard let object else { return }
        for key in object.ownKeys {
            if !allowedKeys.contains(where: { jsStringEquals($0, key) }) {
                throw fail("\(label) contains unsupported field: \(key).")
            }
        }
    }

    // MARK: - validateTrainStore

    /// `validateTrainStore` — jsonspec §15.1.
    ///
    /// The `ids` set is rebuilt here and threaded through every train, which
    /// is what makes duplicate detection a property of the store rather than
    /// of a train.
    @discardableResult
    public static func validateTrainStore(_ store: JSON) throws -> Bool {
        // `!store || typeof store !== "object" || Array.isArray(store)`.
        // `typeof null` is "object" in JavaScript, so the falsiness test is
        // what actually rejects null.
        guard store.isTruthy, case .object = store else {
            throw fail("JSON root must be an object.")
        }
        try assertOnlyKeys(store, ["schema_version", "trains"], "Store")
        let version = store["schema_version"] ?? .null
        if !acceptedSchemaVersions.contains(where: { version == .string($0) }) {
            throw fail(
                "schema_version must be one of \(acceptedSchemaVersions.joined(separator: ", ")).")
        }
        guard case .array(let trains)? = store["trains"] else {
            throw fail("trains must be an array.")
        }
        var ids = Set<String>()
        for (index, train) in trains.enumerated() {
            try validateTrain(train, index: index, ids: &ids)
        }
        return true
    }

    /// The same store rule, on a canonical ``TrainStore``.
    ///
    /// Schema version is still checked here. Each train then goes through
    /// ``recordDiagnostics(_:index:ids:)`` — there is no encode/parse step.
    @discardableResult
    public static func validateTrainStore(_ store: TrainStore) throws -> Bool {
        if !acceptedSchemaVersions.contains(store.schemaVersion) {
            throw fail(
                "schema_version must be one of \(acceptedSchemaVersions.joined(separator: ", ")).")
        }
        var ids = Set<String>()
        for (index, train) in store.trains.enumerated() {
            try validateTrain(train, index: index, ids: &ids)
        }
        return true
    }

    // MARK: - validateTrain

    /// `validateTrain` — jsonspec §15.2/§15.3.
    ///
    /// Dynamic JSON is checked for field types, missing values, and values a
    /// canonical `Train` cannot hold without inventing a default. The record
    /// is then built and passed to the same rule as a typed train. A null row
    /// still crashes with `TypeError`: the JavaScript reads a property off it
    /// before it has established that the row is an object.
    public static func validateTrain(_ train: JSON, index: Int, ids: inout Set<String>) throws {
        try throwFirst(try recordDiagnostics(train, index: index, ids: &ids), index: index)
    }

    /// The same rule, on a canonical train. Decoder defaults are not applied
    /// on the way in: an empty `stop_type` stays empty, and a negative
    /// platform stays negative.
    public static func validateTrain(_ train: Train, index: Int, ids: inout Set<String>) throws {
        try throwFirst(recordDiagnostics(train, index: index, ids: &ids), index: index)
    }

    /// Every business fact about one JSON record, or the one shape fact that
    /// has to be reported before a canonical value can be built.
    ///
    /// A valid id is inserted before a later shape failure, and is not inserted
    /// when the id itself is rejected. That is the set `duplicateIDs` observes.
    public static func recordDiagnostics(
        _ json: JSON, index _: Int, ids: inout Set<String>
    ) throws -> [Diagnostic] {
        do {
            try validateSupportedRegions(json)
        } catch let error as ValidationError {
            return [Diagnostic(path: "region", reason: error.message)]
        } catch {
            throw error
        }
        if let early = try earlyShape(json) { return [early] }
        let id = json["id"]?.stringOrNilIfNotString ?? ""
        if let issue = identityDiagnostic(id, ids: &ids) { return [issue] }
        if let shape = try laterShape(json) { return [shape] }
        let train = try canonicalRecord(json)
        ids.remove(id)
        return recordDiagnostics(train, index: 0, ids: &ids)
    }

    /// Business constraints on one canonical record. The single implementation
    /// the editor, import, and the JSON door share.
    public static func recordDiagnostics(
        _ train: Train, index _: Int, ids: inout Set<String>
    ) -> [Diagnostic] {
        do {
            try validateSupportedRegions(train)
        } catch let error {
            let reason = (error as? ValidationError)?.message ?? String(describing: error)
            return [Diagnostic(path: "region", reason: reason)]
        }
        var issues: [Diagnostic] = []
        let missingID = train.id.isEmpty
        let missingNumber = train.number.isEmpty
        let missingOrigin = train.origin.isEmpty
        let missingDestination = train.destination.isEmpty
        if missingID { issues.append(Diagnostic(path: "id", reason: "id is required.")) }
        if missingNumber { issues.append(Diagnostic(path: "number", reason: "number is required.")) }
        if missingOrigin { issues.append(Diagnostic(path: "origin", reason: "origin is required.")) }
        if missingDestination {
            issues.append(Diagnostic(path: "destination", reason: "destination is required."))
        }
        // The charset check runs only after every required string is present,
        // and only a passing id enters the set — an earlier required-field
        // failure must not reserve the name.
        if !missingID && !missingNumber && !missingOrigin && !missingDestination {
            if let issue = identityDiagnostic(train.id, ids: &ids) { issues.append(issue) }
        }
        if let issue = registryIdentityDiagnostic(
            train.operatorID, field: "operator_id", kind: "op",
            path: "operator_id", location: "", trainRegion: train.region
        ) {
            issues.append(issue)
        }
        if let operatorIDs = train.operatorIDs {
            for (offset, identifier) in operatorIDs.enumerated() {
                let field = "operator_ids[\(offset)]"
                if let issue = registryIdentityDiagnostic(
                    identifier, field: field, kind: "op",
                    path: field, location: "", trainRegion: train.region
                ) {
                    issues.append(issue)
                }
            }
        }
        if let date = train.date, date != undated, !Dates.isValidDateString(date) {
            issues.append(Diagnostic(
                path: "date",
                reason: "date must be \"YYYY-MM-DD\" or \"\(undated)\"."))
        }
        if train.stops.count < 2 {
            issues.append(Diagnostic(
                path: "stops", reason: "stops must contain at least 2 rows."))
        }
        if train.stops.count >= 2 {
            if bothClockTimes(train.stops[0]) {
                issues.append(Diagnostic(
                    path: "stops[0]",
                    reason: "first stop should not need both arrival and departure."))
            }
            let last = train.stops.count - 1
            if bothClockTimes(train.stops[last]) {
                issues.append(Diagnostic(
                    path: "stops[\(last)]",
                    reason: "final stop should not need both arrival and departure."))
            }
        }
        for (offset, stop) in train.stops.enumerated() {
            issues.append(contentsOf: stopDiagnostics(stop, index: offset, trainRegion: train.region))
        }
        if let sections = train.routeSections {
            for (offset, section) in sections.enumerated() {
                issues.append(contentsOf: sectionDiagnostics(
                    section, index: offset, trainRegion: train.region))
            }
        }
        if let policy = train.routePolicy {
            issues.append(contentsOf: policyDiagnostics(policy))
        }
        if let color = train.style?.color, !color.isEmpty, !isValidTrainColor(color) {
            issues.append(Diagnostic(path: "style.color", reason: "style.color must be #RRGGBB."))
        }
        return issues
    }

    private static func identityDiagnostic(_ id: String, ids: inout Set<String>) -> Diagnostic? {
        if id.isEmpty { return Diagnostic(path: "id", reason: "id is required.") }
        if !matchesTrainIDPattern(id) {
            return Diagnostic(
                path: "id",
                reason: "id must match \(trainIDPatternSource) (letters, digits, \"_\" and \"-\").")
        }
        if ids.contains(id) {
            return Diagnostic(path: "id", reason: "duplicate id \(id).")
        }
        ids.insert(id)
        return nil
    }

    private static func bothClockTimes(_ stop: Stop) -> Bool {
        !(stop.arrival ?? "").isEmpty && !(stop.departure ?? "").isEmpty
    }

    private static func stopAt(_ index: Int) -> String { " stop \(index + 1)" }
    private static func sectionAt(_ index: Int) -> String { " route section \(index + 1)" }

    private static var stopTypeListReason: String {
        "stop_type must be one of \(stopTypes.joined(separator: " / "))."
    }

    private static let platformReason =
        "platform_number must be a non-negative integer or null."
    private static let stationCodeReason =
        "n02_station_code must be a six-digit N02_005c, a TDX StationUID, or null."

    /// `st:jp:1` / `op:tw:12`. ASCII only, so this does not use a regular expression.
    private static func matchesRegistryID(_ value: String, kind: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Substring(kind) else { return false }
        switch parts[1] {
        case "jp", "tw", "hk", "mo", "kr", "cn": break
        default: return false
        }
        let sequence = parts[2]
        guard let first = sequence.first, first >= "1", first <= "9" else { return false }
        return sequence.dropFirst().allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func registryIdentityDiagnostic(
        _ value: String?, field: String, kind: String, path: String, location: String,
        trainRegion: String?
    ) -> Diagnostic? {
        guard let value else { return nil }
        let pattern = kind == "st" ? stationIDPatternSource : operatorIDPatternSource
        guard matchesRegistryID(value, kind: kind) else {
            return Diagnostic(
                path: path, reason: "\(field) must match \(pattern).", location: location)
        }
        if let trainRegion, !trainRegion.isEmpty {
            let segment = value.split(separator: ":")[1]
            if String(segment) != trainRegion.lowercased() {
                return Diagnostic(
                    path: path,
                    reason: "\(field) region must equal the train region.",
                    location: location)
            }
        }
        return nil
    }
    private static let institutionReason =
        "route_policy.allowed_institution_type_codes must contain only N02_002 codes 1/2/3/4/5."

    private static func stopDiagnostics(
        _ stop: Stop, index: Int, trainRegion: String?
    ) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        let at = stopAt(index)
        if stop.name.isEmpty {
            issues.append(Diagnostic(
                path: "stops[\(index)].name", reason: "name is required.", location: at))
        }
        if stop.stopType.isEmpty {
            issues.append(Diagnostic(
                path: "stops[\(index)].stop_type", reason: "stop_type is required.", location: at))
        } else if !stopTypes.contains(stop.stopType) {
            issues.append(Diagnostic(
                path: "stops[\(index)].stop_type", reason: stopTypeListReason, location: at))
        }
        if let code = stop.n02StationCode, stationCodeSystem(code) == nil {
            issues.append(Diagnostic(
                path: "stops[\(index)].n02_station_code", reason: stationCodeReason, location: at))
        }
        if let issue = registryIdentityDiagnostic(
            stop.stationID, field: "station_id", kind: "st",
            path: "stops[\(index)].station_id", location: at, trainRegion: trainRegion
        ) {
            issues.append(issue)
        }
        if let platform = stop.platformNumber, platform < 0 {
            issues.append(Diagnostic(
                path: "stops[\(index)].platform_number", reason: platformReason, location: at))
        }
        return issues
    }

    private static func presentEndpoint(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.isEmpty
    }

    private static func sectionDiagnostics(
        _ section: RouteSection, index: Int, trainRegion: String?
    ) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        let at = sectionAt(index)
        let hasFrom = presentEndpoint(section.from) || presentEndpoint(section.fromN02StationCode)
        let hasTo = presentEndpoint(section.to) || presentEndpoint(section.toN02StationCode)
        if !hasFrom || !hasTo {
            issues.append(Diagnostic(
                path: "route_sections[\(index)]",
                reason: "from/to names or official station codes are required.",
                location: at))
        }
        let codes = [
            (section.fromN02StationCode, "from_n02_station_code"),
            (section.toN02StationCode, "to_n02_station_code"),
        ]
        for (code, field) in codes {
            guard let code, stationCodeSystem(code) == nil else { continue }
            issues.append(Diagnostic(
                path: "route_sections[\(index)].\(field)",
                reason: "\(field) must be a six-digit N02_005c, a TDX StationUID, or null.",
                location: at))
            break
        }
        let identities = [
            (section.fromStationID, "from_station_id"),
            (section.toStationID, "to_station_id"),
        ]
        for (value, field) in identities {
            if let issue = registryIdentityDiagnostic(
                value, field: field, kind: "st",
                path: "route_sections[\(index)].\(field)", location: at, trainRegion: trainRegion
            ) {
                issues.append(issue)
            }
        }
        return issues
    }

    private static func policyDiagnostics(_ policy: RoutePolicy) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        if policy.mode != "single_primary_route" {
            issues.append(Diagnostic(
                path: "route_policy.mode",
                reason: "route_policy.mode must be single_primary_route."))
        }
        if policy.jrOnly == nil {
            issues.append(Diagnostic(
                path: "route_policy.jr_only",
                reason: "route_policy.jr_only must be boolean."))
        }
        if policy.allowAlternatives != .some(false) {
            issues.append(Diagnostic(
                path: "route_policy.allow_alternatives",
                reason: "route_policy.allow_alternatives must be false."))
        }
        if policy.allowBrowserStraightLineFallback != .some(false) {
            issues.append(Diagnostic(
                path: "route_policy.allow_browser_straight_line_fallback",
                reason: "route_policy.allow_browser_straight_line_fallback must be false."))
        }
        if let codes = policy.allowedInstitutionTypeCodes {
            let allowed = codes.allSatisfy { code in
                defaultAllowedInstitutionTypeCodes.contains { jsStringEquals($0, code) }
            }
            if !allowed {
                issues.append(Diagnostic(
                    path: "route_policy.allowed_institution_type_codes",
                    reason: institutionReason))
            }
        }
        if let mode = policy.institutionFilterMode, !mode.isEmpty, mode != "soft", mode != "hard" {
            issues.append(Diagnostic(
                path: "route_policy.institution_filter_mode",
                reason: "route_policy.institution_filter_mode must be soft or hard."))
        }
        return issues
    }

    /// Types and missing values that a `Train` would otherwise fill in.
    /// Route confirmation throws here, unwrapped, as the old metadata pass did.
    private static func earlyShape(_ json: JSON) throws -> Diagnostic? {
        for key in ["id", "number", "origin", "destination"] {
            let value = json[key] ?? .null
            guard value.isTruthy, case .string = value else {
                return Diagnostic(path: key, reason: "\(key) is required.")
            }
        }
        for key in ["train_type", "vehicle_type", "company", "number_en", "notes"] {
            if let value = json[key], !value.isString {
                return Diagnostic(path: key, reason: "\(key) must be a string when present.")
            }
        }
        _ = try normalizeImportedRouteConfirmation(json["route_confirmation"])
        if let value = json["operator_id"], value != .null {
            guard value.isString else {
                return Diagnostic(
                    path: "operator_id",
                    reason: "operator_id must match \(operatorIDPatternSource).")
            }
            if let issue = registryIdentityDiagnostic(
                value.stringOrNilIfNotString, field: "operator_id", kind: "op",
                path: "operator_id", location: "",
                trainRegion: (json["region"] ?? .null).stringOrNilIfNotString
            ) {
                return issue
            }
        }
        if let value = json["operator_ids"], value != .null {
            guard case .array(let items) = value else {
                return Diagnostic(
                    path: "operator_ids",
                    reason: "operator_ids must be an array of operator ids.")
            }
            let trainRegion = (json["region"] ?? .null).stringOrNilIfNotString
            var normalized: [String] = []
            var seen = Set<String>()
            for (offset, item) in items.enumerated() {
                let field = "operator_ids[\(offset)]"
                guard let text = item.stringOrNilIfNotString else {
                    return Diagnostic(
                        path: field,
                        reason: "\(field) must match \(operatorIDPatternSource).")
                }
                let trimmed = jsTrim(text)
                if trimmed.isEmpty { continue }
                if let issue = registryIdentityDiagnostic(
                    trimmed, field: field, kind: "op",
                    path: field, location: "", trainRegion: trainRegion
                ) {
                    return issue
                }
                if !seen.insert(trimmed).inserted {
                    return Diagnostic(
                        path: "operator_ids",
                        reason: "operator_ids contains a duplicate.")
                }
                normalized.append(trimmed)
            }
            let operatorText = jsTrim((json["operator_id"] ?? .null).stringOrNilIfNotString ?? "")
            if !operatorText.isEmpty && !normalized.isEmpty {
                return Diagnostic(
                    path: "operator_ids",
                    reason: "operator_id and operator_ids cannot both be set.")
            }
        }
        return nil
    }

    /// Shape that the canonical model cannot store, in the order the old
    /// validator reached it after the id check. A truthy pair of endpoint
    /// times is the both-times rule even when one of them is not a string.
    private static func laterShape(_ json: JSON) throws -> Diagnostic? {
        if let date = json["date"], date != .string(undated) {
            guard case .string = date else {
                return Diagnostic(
                    path: "date",
                    reason: "date must be \"YYYY-MM-DD\" or \"\(undated)\".")
            }
        }
        guard case .array(let stops)? = json["stops"], stops.count >= 2 else {
            return Diagnostic(path: "stops", reason: "stops must contain at least 2 rows.")
        }
        if try endpointBothTruthy(stops[0]) {
            return Diagnostic(
                path: "stops[0]",
                reason: "first stop should not need both arrival and departure.")
        }
        let last = stops.count - 1
        if try endpointBothTruthy(stops[last]) {
            return Diagnostic(
                path: "stops[\(last)]",
                reason: "final stop should not need both arrival and departure.")
        }
        for (offset, stop) in stops.enumerated() {
            if stop == .null { _ = try member(stop, "name") }
            guard case .object = stop else {
                return Diagnostic(
                    path: "stops[\(offset)].name",
                    reason: "name is required.",
                    location: stopAt(offset))
            }
            guard case .bool = stop["ride_segment"] ?? .null else {
                return Diagnostic(
                    path: "stops[\(offset)].ride_segment",
                    reason: "ride_segment must be boolean.",
                    location: stopAt(offset))
            }
            if let platform = platformShape(stop, index: offset) { return platform }
            if let time = timeShape(stop, index: offset) { return time }
            if let value = stop["station_id"], value != .null, !value.isString {
                return Diagnostic(
                    path: "stops[\(offset)].station_id",
                    reason: "station_id must match \(stationIDPatternSource).",
                    location: stopAt(offset))
            }
        }
        if let sections = json["route_sections"], sections.isTruthy {
            guard case .array(let rows) = sections else {
                return Diagnostic(
                    path: "route_sections", reason: "route_sections must be an array.")
            }
            for (offset, section) in rows.enumerated() {
                _ = try member(section, "from")
                guard case .object = section else { continue }
                for field in ["from_station_id", "to_station_id"] {
                    if let value = section[field], value != .null, !value.isString {
                        return Diagnostic(
                            path: "route_sections[\(offset)].\(field)",
                            reason: "\(field) must match \(stationIDPatternSource).",
                            location: sectionAt(offset))
                    }
                }
                for field in ["line_names", "operator_names"] {
                    let values = (section[field] ?? .null).orEmptyArray
                    guard case .array(let items) = values, items.allSatisfy(\.isString) else {
                        return Diagnostic(
                            path: "route_sections[\(offset)].\(field)",
                            reason: "\(field) must be an array of strings.",
                            location: sectionAt(offset))
                    }
                }
            }
        }
        if let policy = json["route_policy"], policy.isTruthy, case .object = policy {
            if let codes = policy["allowed_institution_type_codes"], codes.isTruthy {
                if case .array = codes {
                    // Membership is a business fact, after `String(code)`.
                } else {
                    return Diagnostic(
                        path: "route_policy.allowed_institution_type_codes",
                        reason: institutionReason)
                }
            }
            for field in ["preferred_line_names", "preferred_operator_names"] {
                let values = (policy[field] ?? .null).orEmptyArray
                guard case .array(let items) = values, items.allSatisfy(\.isString) else {
                    return Diagnostic(
                        path: "route_policy.\(field)",
                        reason: "route_policy.\(field) must be an array of strings.")
                }
            }
            if let mode = policy["institution_filter_mode"], mode.isTruthy, !mode.isString {
                return Diagnostic(
                    path: "route_policy.institution_filter_mode",
                    reason: "route_policy.institution_filter_mode must be soft or hard.")
            }
        }
        return nil
    }

    private static func endpointBothTruthy(_ stop: JSON) throws -> Bool {
        try member(stop, "departure").isTruthy && member(stop, "arrival").isTruthy
    }

    private static func platformShape(_ stop: JSON, index: Int) -> Diagnostic? {
        guard let value = stop["platform_number"], value != .null else { return nil }
        if isValidPlatformNumber(value) { return nil }
        if case .number(let number) = value,
            number.isFinite, number < 0, number.rounded(.towardZero) == number,
            Int(exactly: number) != nil
        {
            return nil
        }
        return Diagnostic(
            path: "stops[\(index)].platform_number", reason: platformReason, location: stopAt(index))
    }

    private static func timeShape(_ stop: JSON, index: Int) -> Diagnostic? {
        for field in ["arrival", "actual_arrival", "departure", "actual_departure"] {
            if let value = stop[field], value != .null, !value.isString {
                return Diagnostic(
                    path: "stops[\(index)].\(field)",
                    reason: "\(field) must be a string or null.",
                    location: stopAt(index))
            }
        }
        return nil
    }

    /// Builds a train without the defaults `canonicalStopShape` and
    /// `canonicalRoutePolicy` would write over illegal input.
    private static func canonicalRecord(_ json: JSON) throws -> Train {
        Train(
            id: requiredText(json, "id"),
            date: dateText(json),
            number: requiredText(json, "number"),
            numberEn: optionalText(json, "number_en"),
            trainType: optionalText(json, "train_type"),
            vehicleType: optionalText(json, "vehicle_type"),
            company: optionalText(json, "company"),
            origin: requiredText(json, "origin"),
            destination: requiredText(json, "destination"),
            direction: optionalText(json, "direction"),
            visible: { if case .bool(let flag)? = json["visible"] { return flag }; return nil }(),
            style: styleForValidation(json),
            routePolicy: policyForValidation(json),
            routeSections: sectionsForValidation(json),
            stops: stopsForValidation(json),
            region: optionalText(json, "region"),
            notes: optionalText(json, "notes"),
            routeConfirmation: try normalizeImportedRouteConfirmation(json["route_confirmation"]),
            operatorID: optionalText(json, "operator_id"),
            operatorIDs: optionalOperatorIDs(json["operator_ids"]))
    }

    private static func optionalOperatorIDs(_ value: JSON?) -> [String]? {
        guard let value, case .array(let items) = value else { return nil }
        let ids = items.compactMap(\.stringOrNilIfNotString).map(jsTrim).filter { !$0.isEmpty }
        return ids.isEmpty ? nil : ids
    }

    private static func requiredText(_ json: JSON, _ key: String) -> String {
        json[key]?.stringOrNilIfNotString ?? ""
    }

    private static func optionalText(_ json: JSON, _ key: String) -> String? {
        json[key]?.stringOrNilIfNotString
    }

    private static func dateText(_ json: JSON) -> String? {
        guard let value = json["date"], case .string(let text) = value else { return nil }
        return text
    }

    private static func styleForValidation(_ json: JSON) -> TrainStyle? {
        guard let style = json["style"], case .object = style,
            let color = style["color"], color.isTruthy
        else { return nil }
        return TrainStyle(color: jsToString(color))
    }

    private static func policyForValidation(_ json: JSON) -> RoutePolicy? {
        guard let policy = json["route_policy"], policy.isTruthy else { return nil }
        guard case .object = policy else { return RoutePolicy() }
        let filter: String? = {
            guard let mode = policy["institution_filter_mode"], mode.isTruthy else { return nil }
            return mode.stringOrNilIfNotString
        }()
        return RoutePolicy(
            mode: policy["mode"]?.stringOrNilIfNotString,
            jrOnly: boolOrNil(policy["jr_only"]),
            allowAlternatives: boolOrNil(policy["allow_alternatives"]),
            allowBrowserStraightLineFallback: boolOrNil(
                policy["allow_browser_straight_line_fallback"]),
            allowedInstitutionTypeCodes: institutionCodes(policy),
            preferredLineNames: stringArray(policy["preferred_line_names"]),
            preferredOperatorNames: stringArray(policy["preferred_operator_names"]),
            institutionFilterMode: filter)
    }

    private static func boolOrNil(_ value: JSON?) -> Bool? {
        if case .bool(let flag)? = value { return flag }
        return nil
    }

    private static func institutionCodes(_ policy: JSON) -> [String]? {
        guard let value = policy["allowed_institution_type_codes"], value.isTruthy,
            case .array(let items) = value
        else { return nil }
        return items.map(jsToString)
    }

    private static func stringArray(_ value: JSON?) -> [String]? {
        guard let value, value.isTruthy, case .array(let items) = value else { return nil }
        return items.compactMap(\.stringOrNilIfNotString)
    }

    private static func sectionsForValidation(_ json: JSON) -> [RouteSection]? {
        guard let sections = json["route_sections"], sections.isTruthy,
            case .array(let rows) = sections
        else { return nil }
        return rows.map(sectionForValidation)
    }

    private static func sectionForValidation(_ section: JSON) -> RouteSection {
        guard case .object = section else { return RouteSection() }
        return RouteSection(
            from: truthyText(section["from"]),
            to: truthyText(section["to"]),
            fromN02StationCode: codeText(section["from_n02_station_code"]),
            toN02StationCode: codeText(section["to_n02_station_code"]),
            fromStationID: (section["from_station_id"] ?? .null).stringOrNilIfNotString,
            toStationID: (section["to_station_id"] ?? .null).stringOrNilIfNotString)
    }

    private static func truthyText(_ value: JSON?) -> String? {
        guard let value, value.isTruthy else { return nil }
        return jsToString(value)
    }

    /// Absent and JSON null become nil. An empty string stays empty so it
    /// still fails the station-code rule; `orNullString` would hide it.
    private static func codeText(_ value: JSON?) -> String? {
        guard let value, value != .null else { return nil }
        return jsToString(value)
    }

    private static func stopsForValidation(_ json: JSON) -> [Stop] {
        guard case .array(let rows)? = json["stops"] else { return [] }
        return rows.map { row in
            guard case .object = row else {
                return Stop(name: "", stopType: "", rideSegment: false)
            }
            let ride: Bool
            if case .bool(let flag) = row["ride_segment"] ?? .null { ride = flag } else { ride = false }
            let stopType = (row["stop_type"] ?? .null).isTruthy
                ? jsToString(row["stop_type"] ?? .null) : ""
            let name = (row["name"] ?? .null).isTruthy ? jsToString(row["name"] ?? .null) : ""
            return Stop(
                name: name,
                n02StationCode: codeText(row["n02_station_code"]),
                platformNumber: integerPlatform(row["platform_number"]),
                arrival: timeText(row["arrival"]),
                actualArrival: timeText(row["actual_arrival"]),
                departure: timeText(row["departure"]),
                actualDeparture: timeText(row["actual_departure"]),
                stopType: stopType,
                rideSegment: ride,
                stationID: (row["station_id"] ?? .null).stringOrNilIfNotString)
        }
    }

    private static func timeText(_ value: JSON?) -> String? {
        guard let value, case .string(let text) = value else { return nil }
        return text
    }

    private static func integerPlatform(_ value: JSON?) -> Int? {
        guard case .number(let number)? = value, let int = Int(exactly: number) else { return nil }
        return int
    }

    /// Property access that reproduces JavaScript's `TypeError` on null.
    ///
    /// Reading a property off `null` or `undefined` throws in JavaScript;
    /// reading one off a number, a string or a boolean quietly yields
    /// `undefined`. The validator relies on the second half by accident and
    /// falls over on the first.
    private static func member(_ value: JSON, _ key: String) throws -> JSON {
        if value == .null {
            throw ValidationError(
                kind: .typeError,
                message: "Cannot read properties of null (reading '\(key)')")
        }
        return value[key] ?? .null
    }

    // MARK: - §19: lenient inbound

    /// `parseImportedCanonicalStore` for a pasted string — jsonspec §1.2.
    public static func parseImportedCanonicalStore(text: String) throws -> JSON {
        try parseImportedCanonicalStore(value: JSON.parse(text))
    }

    /// `parseImportedCanonicalStore` for an already-parsed value.
    ///
    /// Three shapes are accepted: a full store, a bare trains array, and a
    /// single train object. The full-store branch is the only one that checks
    /// `schema_version` or applies the key whitelist — which is how a train
    /// object carrying a non-array `trains` key slips past both, since
    /// `Array.isArray` is the only thing that key is ever consulted through.
    public static func parseImportedCanonicalStore(value parsed: JSON) throws -> JSON {
        if case .array = parsed {
            return .object(JSON.Object([("schema_version", .string(schemaVersion)), ("trains", parsed)]))
        }
        guard parsed.isTruthy, case .object = parsed else {
            throw fail("JSON root must be a store object, a trains array, or one train object.")
        }
        if case .array? = parsed["trains"] {
            try assertOnlyKeys(parsed, ["schema_version", "trains"], "Store")
            let version = parsed["schema_version"] ?? .null
            if !acceptedSchemaVersions.contains(where: { version == .string($0) }) {
                throw fail(
                    "schema_version must be one of \(acceptedSchemaVersions.joined(separator: ", "))."
                )
            }
            return parsed
        }
        if parsed["id"]?.isTruthy == true, parsed["stops"]?.isTruthy == true {
            return .object(
                JSON.Object([("schema_version", .string(schemaVersion)), ("trains", .array([parsed]))]))
        }
        throw fail("JSON must contain a trains array, be a trains array, or be a single train object.")
    }

    /// `normalizeImportedStop` — the §7.1 whitelist plus the §18 defaults.
    public static func normalizeImportedStop(_ stop: JSON) throws -> Stop {
        guard stop.isTruthy, case .object = stop else {
            throw fail("Each stop must be an object.")
        }
        try assertOnlyKeys(
            stop,
            [
                "name", "n02_station_code", "station_id", "platform_number", "arrival", "actual_arrival",
                "departure", "actual_departure",
                "stop_type", "ride_segment", "route_editing",
            ],
            "Stop")
        // ACCEPTS: the guard is key PRESENCE, not a usable value, so
        // `{"name": null}` imports as a stop with an empty name and is only
        // caught later by validateTrain.
        guard stop.hasOwnKey("name") else { throw fail("Each stop must contain name.") }
        guard isValidPlatformNumber(stop["platform_number"]) else {
            throw fail("platform_number must be a non-negative integer or null.")
        }
        if let metadata = stop["route_editing"], metadata != .null {
            guard let id = metadata["visit_id"]?.stringOrNilIfNotString,
                  UUID(uuidString: id) != nil else {
                throw fail("route_editing must contain a valid visit_id.")
            }
            if let generatedBy = metadata["generated_by"], generatedBy != .null,
               generatedBy.stringOrNilIfNotString == nil {
                throw fail("route_editing generated_by must be a string or null.")
            }
        }
        return canonicalStopShape(stop)
    }

    /// `normalizeImportedRouteSection` — §6.1/§6.1b whitelist and defaults.
    ///
    /// §13.4: `from`/`to` are optional, and when absent are resolved from the
    /// codes through the station table, so that name matching, the §6.4
    /// branch checks and the tooltips keep working on a lean stored section.
    public static func normalizeImportedRouteSection(
        _ section: JSON, stations: StationTable = .empty
    ) throws -> RouteSection {
        guard section.isTruthy, case .object = section else {
            throw fail("Each route_section must be an object.")
        }
        try assertOnlyKeys(
            section,
            [
                "from", "to", "from_n02_station_code", "to_n02_station_code",
                "from_station_id", "to_station_id",
                "line_names", "operator_names", "line_ids", "section_codes", "section_codes_origin", "number", "name",
            ],
            "Route section")

        let fromCode = (section["from_n02_station_code"] ?? .null).orNullString
            .map(StationCodeAliases.canonical)
        let toCode = (section["to_n02_station_code"] ?? .null).orNullString
            .map(StationCodeAliases.canonical)
        var normalized = RouteSection(
            from: (section["from"] ?? .null).stringOrNilIfFalsy ?? stations.nameForCode(fromCode),
            to: (section["to"] ?? .null).stringOrNilIfFalsy ?? stations.nameForCode(toCode),
            fromN02StationCode: fromCode,
            toN02StationCode: toCode,
            fromStationID: (section["from_station_id"] ?? .null).stringOrNilIfNotString,
            toStationID: (section["to_station_id"] ?? .null).stringOrNilIfNotString,
            // `Array.isArray(x) ? x.map(String).filter(Boolean) : []` — the
            // import path always produces an array, never an absent field, so
            // these are `?? []` and not left nil. A section that comes back
            // with no hints says "unconstrained" explicitly; leaving the key
            // out would be the export path's shape, not this one's.
            lineNames: mapStringFilterBoolean(section["line_names"]) ?? [],
            operatorNames: mapStringFilterBoolean(section["operator_names"]) ?? [],
            lineIDs: mapStringFilterBoolean(section["line_ids"]),
            sectionCodes: mapStringFilterBoolean(section["section_codes"]))
        if let origin = section["section_codes_origin"], origin != .null {
            guard let value = origin.stringOrNilIfNotString,
                  let parsed = RecordedRouteAdmission.SectionCodesOrigin(rawValue: value) else {
                throw fail("Route section section_codes_origin must be corridorPreference or packageInference.")
            }
            normalized.sectionCodesOrigin = parsed
        }
        // Optional per-section branch train number / name: some limited
        // expresses run a branch portion under a DIFFERENT 号 (はやぶさ↔こまち,
        // しおかぜ↔いしづち).
        if let number = section["number"], number.isTruthy { normalized.number = jsToString(number) }
        if let name = section["name"], name.isTruthy { normalized.name = jsToString(name) }
        return normalized
    }

    /// `normalizeImportedTrain` — the §3.1 whitelist, then canonical defaults.
    ///
    /// This is a *different* front door from ``validateTrain(_:index:ids:)``
    /// and the two disagree on purpose-looking cases: this one enforces a key
    /// whitelist that the validator never applies, and coerces a numeric
    /// `train_type` to `""` where the validator rejects it outright.
    ///
    /// `country` decides only one thing — whether the company name goes
    /// through the Taiwanese canonicalisation (§3.4).
    public static func normalizeImportedTrain(
        _ train: JSON,
        fallbackDate: String? = nil,
        country: String = "jp",
        stations: StationTable = .empty
    ) throws -> Train {
        guard train.isTruthy, case .object = train else {
            throw fail("Each train must be an object.")
        }
        guard ["jp", "tw", "hk", "mo", "kr", "cn"].contains(country.lowercased()) else {
            throw fail("Unsupported journey region: \(country).")
        }
        try validateSupportedRegions(train)
        // The JavaScript's fourteen keys, plus this app's own train metadata.
        //
        // `region` is shared with the web import/export path. It has to be
        // accepted here because
        // `normalizeExportTrain` deliberately CARRIES it (see the note there)
        // and `StoreOperations.json(_:)` writes it — so without this line the
        // app rejected its own export on the way back in, one error per
        // journey, and a backup it had just written could not be restored.
        try assertOnlyKeys(
            train,
            [
                "id", "date", "number", "number_en", "train_type", "vehicle_type", "company", "operator_id", "operator_ids", "origin",
                "destination", "direction", "visible", "style", "route_policy",
                "route_sections", "stops", "region", "notes", "journey_group", "route_confirmation",
            ],
            "Train")

        guard let idValue = train["id"], idValue.isTruthy else {
            throw fail("Each train must contain id.")
        }
        let id = jsToString(idValue)
        guard train["number"]?.isTruthy == true else { throw fail("Train \(id) must contain number.") }
        guard train["origin"]?.isTruthy == true else { throw fail("Train \(id) must contain origin.") }
        guard train["destination"]?.isTruthy == true else {
            throw fail("Train \(id) must contain destination.")
        }
        guard case .array(let stops)? = train["stops"], stops.count >= 2 else {
            throw fail("Train \(id) must contain at least 2 stops.")
        }

        // The Latin name is its own field. A store written before it had one
        // carried it inside the caption — 「はるか38号 (Haruka 38) (1038M)」 —
        // and is split here, once, on the way in; a store that already says
        // `number_en` keeps its caption exactly as written, whatever its
        // shape. An explicit blank means "none", the same as absent.
        let caption = jsToString(train["number"] ?? .null)
        let explicitLatin = (train["number_en"] ?? .null).stringOrNilIfNotString
            .map(jsTrim).flatMap { $0.isEmpty ? nil : $0 }
        let service =
            explicitLatin.map { ServiceCaption(primary: caption, latinName: $0) }
            ?? ServiceCaption.split(caption)

        return Train(
            id: id,
            date: Dates.normalizeTrainDate(
                id: id, date: (train["date"] ?? .null).stringOrNilIfNotString,
                fallback: fallbackDate),
            number: service.primary,
            numberEn: service.latinName,
            // A non-string is dropped rather than coerced — which is exactly
            // where this path and validateTrain part company.
            trainType: (train["train_type"] ?? .null).stringOrNilIfNotString.map(jsTrim) ?? "",
            vehicleType: (train["vehicle_type"] ?? .null).stringOrNilIfNotString.map(jsTrim),
            company: normalizeTrainCompany(train["company"], country: country),
            origin: jsToString(train["origin"] ?? .null),
            destination: jsToString(train["destination"] ?? .null),
            direction: (train["direction"] ?? .null).stringOrNilIfFalsy ?? "down",
            // `!== false`, so 0 and null both mean visible.
            visible: (train["visible"] ?? .null) != .bool(false),
            style: canonicalStyle(train["style"]),
            routePolicy: canonicalRoutePolicy(train["route_policy"]),
            routeSections: try {
                guard case .array(let rows)? = train["route_sections"] else { return [] }
                return try rows.map { try normalizeImportedRouteSection($0, stations: stations) }
            }(),
            stops: try stops.map(normalizeImportedStop),
            // Read back for the same reason the export writes it: a ride that
            // says which region it is in must not have to be re-derived, and
            // `Region.resolved` would otherwise answer "Japan" for a Taiwanese
            // store on the launch that loaded it.
            region: (train["region"] ?? .null).stringOrNilIfFalsy,
            notes: (train["notes"] ?? .null).stringOrNilIfNotString.map(jsTrim),
            journeyGroup: try normalizeImportedJourneyGroup(train["journey_group"]),
            routeConfirmation: try normalizeImportedRouteConfirmation(train["route_confirmation"]),
            operatorID: (train["operator_id"] ?? .null).stringOrNilIfNotString,
            operatorIDs: optionalOperatorIDs(train["operator_ids"]))
    }

    private static func normalizeImportedRouteConfirmation(_ value: JSON?) throws -> RouteConfirmation? {
        guard let value, value != .null else { return nil }
        guard let raw = value.stringOrNilIfNotString, let confirmation = RouteConfirmation(rawValue: raw) else {
            throw fail("Route confirmation must be pending or confirmed.")
        }
        return confirmation
    }

    private static func normalizeImportedJourneyGroup(_ value: JSON?) throws -> JourneyGroup? {
        guard let value, value != .null else { return nil }
        guard case .object = value,
              let id = value["id"]?.stringOrNilIfNotString, !id.isEmpty,
              let name = value["name"]?.stringOrNilIfNotString
        else { throw fail("Journey group must contain a nonempty string id and a string name.") }
        return JourneyGroup(id: id, name: name)
    }

    /// `normalizeTrainCompany` — trim, then canonicalise for Taiwan only.
    ///
    /// jsonspec §3.4: Taiwanese legacy institution names migrate to the short
    /// forms (臺灣鐵路管理局 → 台鐵), while `operator_names` elsewhere keeps
    /// the full official name. Japan does not go through this at all, so the
    /// same train imports differently depending on the active country.
    public static func normalizeTrainCompany(_ value: JSON?, country: String) -> String {
        let company = (value ?? .null).stringOrNilIfNotString.map(jsTrim) ?? ""
        return country == "tw"
            ? OperatorBranding.normalizeTaiwanCompanyName(company) : company
    }

    // MARK: - §18: the canonical shapes

    /// `canonicalStopShape` — the seven base fields every time, plus actual
    /// times when they have been recorded.
    public static func canonicalStopShape(_ stop: JSON) -> Stop {
        Stop(
            name: (stop["name"] ?? .null).isTruthy ? jsToString(stop["name"] ?? .null) : "",
            n02StationCode: (stop["n02_station_code"] ?? .null).orNullString
                .map(StationCodeAliases.canonical),
            platformNumber: platformNumber(stop["platform_number"]),
            arrival: normalizeNullableTime(stop["arrival"]),
            actualArrival: normalizeNullableTime(stop["actual_arrival"]),
            departure: normalizeNullableTime(stop["departure"]),
            actualDeparture: normalizeNullableTime(stop["actual_departure"]),
            stopType: (stop["stop_type"] ?? .null).stringOrNilIfFalsy ?? "passenger_stop",
            rideSegment: (stop["ride_segment"] ?? .null).isTruthy,
            routeEditing: stop["route_editing"].flatMap { metadata in
                guard let text = metadata["visit_id"]?.stringOrNilIfNotString,
                      let id = UUID(uuidString: text) else { return nil }
                return Stop.RouteEditingMetadata(
                    visitID: id, generatedBy: metadata["generated_by"]?.stringOrNilIfNotString)
            },
            stationID: (stop["station_id"] ?? .null).stringOrNilIfNotString)
    }

    /// `canonicalStopShape` for a stop that is already typed — the export
    /// path calls the same function on its in-memory stops.
    ///
    /// It is not the identity even here: an empty station code collapses to
    /// nil (`stop.n02_station_code || null`), a whitespace-only time collapses
    /// to nil, and an empty `stop_type` becomes `passenger_stop`.
    public static func canonicalStopShape(_ stop: Stop) -> Stop {
        Stop(
            name: stop.name,
            n02StationCode: stop.n02StationCode.flatMap {
                $0.isEmpty ? nil : StationCodeAliases.canonical($0)
            },
            platformNumber: stop.platformNumber.flatMap { $0 >= 0 ? $0 : nil },
            arrival: normalizeNullableTime(stop.arrival.map(JSON.string)),
            actualArrival: normalizeNullableTime(stop.actualArrival.map(JSON.string)),
            departure: normalizeNullableTime(stop.departure.map(JSON.string)),
            actualDeparture: normalizeNullableTime(stop.actualDeparture.map(JSON.string)),
            stopType: stop.stopType.isEmpty ? "passenger_stop" : stop.stopType,
            rideSegment: stop.rideSegment,
            routeEditing: stop.routeEditing,
            stationID: stop.stationID)
    }

    private static func platformNumber(_ value: JSON?) -> Int? {
        guard isValidPlatformNumber(value), case .number(let number)? = value else { return nil }
        return Int(number)
    }

    /// `normalizeNullableTime` — trim, and collapse a blank to null.
    ///
    /// It never parses. A non-string is returned unchanged by the JavaScript,
    /// which is how the number 830 survives import and is then rejected by
    /// the validator; here that shape simply cannot be represented by
    /// `Stop.arrival`, so it becomes nil. The fixture records the JavaScript's
    /// answer for that case and the test reads it as a documented divergence
    /// of the *typed model*, not of the rule.
    public static func normalizeNullableTime(_ value: JSON?) -> String? {
        guard let value, value != .null else { return nil }
        guard case .string(let text) = value else { return nil }
        let trimmed = jsTrim(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `canonicalStyle` — only `color` is per-train now.
    ///
    /// Line width is a global setting and unridden intervals are hidden
    /// entirely, so `weight` / `unridden_opacity` are no longer stored per
    /// train; any inbound values are dropped here (§4.1).
    public static func canonicalStyle(_ style: JSON?) -> TrainStyle {
        let color = style?["color"]
        return TrainStyle(
            color: (color?.isTruthy ?? false) ? jsToString(color!) : defaultTrainColor)
    }

    /// `canonicalRoutePolicy` — every field written, defaults filled.
    public static func canonicalRoutePolicy(_ policy: JSON?) -> RoutePolicy {
        RoutePolicy(
            mode: "single_primary_route",
            // `=== true`, so a truthy 1 becomes false.
            jrOnly: policy?["jr_only"] == .bool(true),
            allowAlternatives: false,
            allowBrowserStraightLineFallback: false,
            allowedInstitutionTypeCodes: {
                // `|| [...DEFAULT]` — note this passes the inbound array
                // through untouched rather than mapping it through String(),
                // unlike the two preferred_* arrays below.
                guard case .array(let codes)? = policy?["allowed_institution_type_codes"],
                    policy?["allowed_institution_type_codes"]?.isTruthy == true
                else { return defaultAllowedInstitutionTypeCodes }
                return codes.map(jsToString)
            }(),
            preferredLineNames: mapStringFilterBoolean(policy?["preferred_line_names"]) ?? [],
            preferredOperatorNames: mapStringFilterBoolean(policy?["preferred_operator_names"]) ?? [],
            institutionFilterMode: (policy?["institution_filter_mode"] ?? .null).stringOrNilIfFalsy
                ?? "soft")
    }

    /// `values.map(String).filter(Boolean)` — nil when the input is not an
    /// array, which is how a non-array becomes `[]` at every call site.
    private static func mapStringFilterBoolean(_ value: JSON?) -> [String]? {
        guard case .array(let items)? = value else { return nil }
        return items.map(jsToString).filter { !$0.isEmpty }
    }

    // MARK: - §18: the export path

    /// The station lookups the export path reaches for through bare globals.
    ///
    /// Injected rather than assumed, because the answer genuinely differs
    /// between "the app has loaded its datasets" and "it has not", and both
    /// are real states — the second is what every boot and every import runs
    /// in until `app-datasets.js` has fetched anything. ``empty`` is that
    /// state, and it is what `port-fixtures/validation.json` was generated
    /// in, which is what makes the export path a pure function of the store.
    public struct StationTable: Sendable {
        /// Whether export resolved a stop to a station feature.
        ///
        /// The JavaScript export calls `resolveStationForTrain`. This app
        /// injects the answer. Two levels of "no", because the JavaScript
        /// distinguishes them: `from ? stationCode(from) : fromStop.n02_station_code || null`
        /// falls back to the stop's own code only when NO station resolved.
        /// A station that resolved but carries no code of its own yields
        /// null, and the stop's code is not consulted.
        public enum Resolution: Sendable, Equatable {
            /// Nothing resolved. The JavaScript twin's null.
            case unresolved
            /// A station feature, whose own `stationCode` may still be nil.
            case resolved(code: String?)
        }

        /// `stationNameForCode` — `""` when the code is unknown, never nil.
        public var nameForCode: @Sendable (String?) -> String
        /// Injected stop resolution, reduced to its code.
        public var resolveStop: @Sendable (Stop, Train) -> Resolution

        public init(
            nameForCode: @escaping @Sendable (String?) -> String,
            resolveStop: @escaping @Sendable (Stop, Train) -> Resolution
        ) {
            self.nameForCode = nameForCode
            self.resolveStop = resolveStop
        }

        /// No station data loaded.
        public static let empty = StationTable(
            nameForCode: { _ in "" }, resolveStop: { _, _ in .unresolved })
    }

    /// `buildCanonicalTrainStore` — what the export textarea and the server
    /// save both write.
    public static func buildCanonicalTrainStore(
        _ trains: [Train], country: String = "jp", stations: StationTable = .empty
    ) -> TrainStore {
        TrainStore(
            schemaVersion: schemaVersion,
            trains: trains.map { normalizeExportTrain($0, country: country, stations: stations) })
    }

    /// `normalizeExportTrain`.
    ///
    /// Route geometry is deliberately not persisted: it is cached in
    /// IndexedDB and re-solved on a miss, and embedding it here was about
    /// 96 % of the file.
    public static func normalizeExportTrain(
        _ train: Train, country: String = "jp", stations: StationTable = .empty
    ) -> Train {
        Train(
            id: train.id,
            date: Dates.normalizeTrainDate(train),
            number: train.number,
            // Written only when there is one — see `Train.numberEn`.
            numberEn: train.numberEn.flatMap { $0.isEmpty ? nil : $0 },
            trainType: train.trainType ?? "",
            vehicleType: train.vehicleType,
            company: normalizeTrainCompany(train.company.map(JSON.string), country: country),
            origin: train.origin,
            destination: train.destination,
            direction: (train.direction?.isEmpty == false) ? train.direction : "down",
            visible: train.visible != false,
            style: canonicalStyle(train.style.map { .object(JSON.Object([("color", $0.color.map(JSON.string) ?? .null)])) }),
            routePolicy: canonicalRoutePolicy(routePolicyJSON(train.routePolicy)),
            routeSections: (train.requiresRouteConfirmation
                ? (train.routeSections ?? []).map(normalizeExportRouteSection)
                : rideRouteSections(for: train, stations: stations))
                .map { leanExportSection($0, stations: stations) },
            stops: train.stops.map(canonicalStopShape),
            // Carried, not derived. `region` is this app's own field (see
            // `Train.region`) and the export is the only path to disk, so
            // dropping it here would lose the answer on every save and make
            // every load re-derive it.
            region: train.region,
            notes: train.notes,
            journeyGroup: train.journeyGroup,
            routeConfirmation: train.routeConfirmation,
            operatorID: train.operatorID,
            operatorIDs: train.operatorIDs)
    }

    /// Route inputs for solving and geometry display. Pending hints are
    /// archived without being promoted to a physical route.
    public static func routeSectionsForSolving(
        for train: Train, stations: StationTable = .empty
    ) -> [RouteSection] {
        guard !train.requiresRouteConfirmation else { return [] }
        return rideRouteSections(for: train, stations: stations)
    }

    /// Restore the endpoint names that the browser import path resolves from
    /// station codes before it builds a route-solve cache key. Bundled stores
    /// deliberately omit these redundant names. Only an exact canonical-code
    /// match in the train's stop list is used; explicit and unknown names are
    /// left untouched.
    public static func restoringRouteSectionEndpointNames(_ train: Train) -> Train {
        var restored = train
        var namesByCode: [String: String] = [:]
        for stop in train.stops {
            guard !stop.name.isEmpty,
                  let code = stop.n02StationCode, !code.isEmpty else { continue }
            namesByCode[StationCodeAliases.canonical(code)] = stop.name
        }
        restored.routeSections = train.routeSections?.map { section in
            var section = section
            if section.from?.isEmpty != false,
               let code = section.fromN02StationCode, !code.isEmpty {
                section.from = namesByCode[StationCodeAliases.canonical(code)]
            }
            if section.to?.isEmpty != false,
               let code = section.toN02StationCode, !code.isEmpty {
                section.to = namesByCode[StationCodeAliases.canonical(code)]
            }
            return section
        }
        return restored
    }

    /// `getRideRouteSectionsForTrain` — one section per adjacent stop pair.
    ///
    /// Keep a complete authored boundary chain through every recorded stop.
    /// Otherwise recompute adjacent pairs, reusing only matching sections so
    /// a hand-edited stop list cannot retain an unrelated physical alignment.
    static func rideRouteSections(for train: Train, stations: StationTable) -> [RouteSection] {
        let stops = train.stops
        let sections = train.routeSections ?? []
        if completeRecordedRouteSectionChain(sections, stops: stops) {
            return sections.map(normalizeExportRouteSection)
        }
        var fallbackIndex: RouteSectionPairIndex?
        var calculated: [RouteSection] = []
        for index in 0..<max(stops.count - 1, 0) {
            let fromStop = stops[index]
            let toStop = stops[index + 1]
            if let existing = findRouteSection(
                sections, fromStop, toStop, preferring: index, fallbackIndex: &fallbackIndex
            ) {
                calculated.append(normalizeExportRouteSection(existing))
                continue
            }
            let endpointCode = { (stop: Stop) -> String? in
                switch stations.resolveStop(stop, train) {
                case .resolved(let code): code
                case .unresolved: stop.n02StationCode.flatMap { $0.isEmpty ? nil : $0 }
                }
            }
            calculated.append(
                RouteSection(
                    from: fromStop.name,
                    to: toStop.name,
                    fromN02StationCode: endpointCode(fromStop),
                    toN02StationCode: endpointCode(toStop),
                    fromStationID: fromStop.stationID,
                    toStationID: toStop.stationID))
        }
        return calculated
    }

    /// Keep authored physical boundaries without inventing timetable visits.
    /// Only section endpoints establish recorded-call coverage; an interval's
    /// interior is not evidence that a particular passenger call was traversed.
    private static func completeRecordedRouteSectionChain(
        _ sections: [RouteSection], stops: [Stop]
    ) -> Bool {
        RecordedRouteMapping(stops: stops, sections: sections) != nil
    }

    /// `findRouteSectionForStopPair` — the section at the same index if it
    /// matches, otherwise the first one anywhere that does.
    private static func findRouteSection(
        _ sections: [RouteSection], _ fromStop: Stop, _ toStop: Stop, preferring index: Int,
        fallbackIndex: inout RouteSectionPairIndex?
    ) -> RouteSection? {
        if index < sections.count, matches(sections[index], fromStop, toStop) {
            return sections[index]
        }
        guard !sections.isEmpty else { return nil }
        // Aligned records need no index. Build it on the first missed pair so
        // stop insertion or reordered sections still take one linear pass.
        if fallbackIndex == nil { fallbackIndex = RouteSectionPairIndex(sections) }
        guard let match = fallbackIndex?.firstMatch(fromStop, toStop) else { return nil }
        return sections[match]
    }

    /// Swift String equality folds canonical Unicode equivalents; the reuse
    /// rule compares JavaScript strings, so keys retain their UTF-16 units.
    private enum RouteSectionEndpointKey: Hashable {
        case code([UInt16])
        case name([UInt16])

        static func keys(code: String?, name: String?) -> [Self] {
            var keys: [Self] = []
            if let code, !code.isEmpty {
                keys.append(.code(Array(StationCodeAliases.canonical(code).utf16)))
            }
            if let name, !name.isEmpty { keys.append(.name(Array(name.utf16))) }
            return keys
        }
    }

    private struct RouteSectionPairKey: Hashable {
        let from: RouteSectionEndpointKey
        let to: RouteSectionEndpointKey
    }

    private struct RouteSectionPairIndex {
        var candidates: [RouteSectionPairKey: [Int]] = [:]
        let sections: [RouteSection]

        init(_ sections: [RouteSection]) {
            self.sections = sections
            for (index, section) in sections.enumerated() {
                for from in RouteSectionEndpointKey.keys(code: section.fromN02StationCode, name: section.from) {
                    for to in RouteSectionEndpointKey.keys(code: section.toN02StationCode, name: section.to) {
                        candidates[RouteSectionPairKey(from: from, to: to), default: []].append(index)
                    }
                }
            }
        }

        func firstMatch(_ from: Stop, _ to: Stop) -> Int? {
            var earliest: Int?
            // Either endpoint may match by code or fill an absent identity by
            // name. The matcher still rejects names with conflicting codes.
            for fromKey in RouteSectionEndpointKey.keys(code: from.n02StationCode, name: from.name) {
                for toKey in RouteSectionEndpointKey.keys(code: to.n02StationCode, name: to.name) {
                    let key = RouteSectionPairKey(from: fromKey, to: toKey)
                    guard let match = candidates[key]?.first(where: {
                        TrainValidation.matches(sections[$0], from, to)
                    }) else { continue }
                    earliest = earliest.map { min($0, match) } ?? match
                }
            }
            return earliest
        }
    }

    /// `routeSectionMatchesStopPair`.
    ///
    /// Names fill absent identities; they cannot override conflicting codes.
    private static func matches(_ section: RouteSection, _ fromStop: Stop, _ toStop: Stop) -> Bool {
        func endpoint(_ stop: Stop, code: String?, name: String?) -> Bool {
            let stopCode = stop.n02StationCode.flatMap { $0.isEmpty ? nil : StationCodeAliases.canonical($0) }
            let sectionCode = code.flatMap { $0.isEmpty ? nil : StationCodeAliases.canonical($0) }
            if let stopCode, let sectionCode { return jsStringEquals(stopCode, sectionCode) }
            return !stop.name.isEmpty && jsStringEquals(stop.name, name ?? "")
        }
        return endpoint(fromStop, code: section.fromN02StationCode, name: section.from)
            && endpoint(toStop, code: section.toN02StationCode, name: section.to)
    }

    /// `normalizeExportRouteSection` — names default to `""`, hint arrays are
    /// kept only when non-empty.
    private static func normalizeExportRouteSection(_ section: RouteSection) -> RouteSection {
        var normalized = RouteSection(
            from: section.from ?? "",
            to: section.to ?? "",
            fromN02StationCode: section.fromN02StationCode.flatMap {
                $0.isEmpty ? nil : StationCodeAliases.canonical($0)
            },
            toN02StationCode: section.toN02StationCode.flatMap {
                $0.isEmpty ? nil : StationCodeAliases.canonical($0)
            },
            fromStationID: section.fromStationID.flatMap { $0.isEmpty ? nil : $0 },
            toStationID: section.toStationID.flatMap { $0.isEmpty ? nil : $0 })
        if let lines = section.lineNames, !lines.isEmpty { normalized.lineNames = lines }
        if let operators = section.operatorNames, !operators.isEmpty {
            normalized.operatorNames = operators
        }
        if let ids = section.lineIDs, !ids.isEmpty { normalized.lineIDs = ids }
        if let codes = section.sectionCodes, !codes.isEmpty {
            normalized.sectionCodes = codes
            normalized.sectionCodesOrigin = section.sectionCodesOrigin
        }
        if let number = section.number, !number.isEmpty { normalized.number = number }
        if let name = section.name, !name.isEmpty { normalized.name = name }
        return normalized
    }

    /// `leanExportSection` — drop an endpoint name the code can reconstruct.
    ///
    /// jsonspec §13.4: the station name is a per-station constant, kept once
    /// on the stop, so repeating it in every section only bloats the archive.
    /// A name with no code, or one that *disagrees* with the code's
    /// authoritative name (an alias or a deliberate override), is kept —
    /// which is why the empty station table keeps all of them.
    private static func leanExportSection(_ section: RouteSection, stations: StationTable)
        -> RouteSection
    {
        let fromCode = section.fromN02StationCode.flatMap {
            $0.isEmpty ? nil : StationCodeAliases.canonical($0)
        }
        let toCode = section.toN02StationCode.flatMap {
            $0.isEmpty ? nil : StationCodeAliases.canonical($0)
        }
        var out = RouteSection(
            fromN02StationCode: fromCode, toN02StationCode: toCode,
            fromStationID: section.fromStationID.flatMap { $0.isEmpty ? nil : $0 },
            toStationID: section.toStationID.flatMap { $0.isEmpty ? nil : $0 })
        if let from = section.from, !from.isEmpty,
            fromCode == nil || !jsStringEquals(stations.nameForCode(fromCode), from)
        {
            out.from = from
        }
        if let to = section.to, !to.isEmpty,
            toCode == nil || !jsStringEquals(stations.nameForCode(toCode), to)
        {
            out.to = to
        }
        if let lines = section.lineNames, !lines.isEmpty { out.lineNames = lines }
        if let operators = section.operatorNames, !operators.isEmpty { out.operatorNames = operators }
        if let ids = section.lineIDs, !ids.isEmpty { out.lineIDs = ids }
        if let codes = section.sectionCodes, !codes.isEmpty {
            out.sectionCodes = codes
            out.sectionCodesOrigin = section.sectionCodesOrigin
        }
        if let number = section.number, !number.isEmpty { out.number = number }
        if let name = section.name, !name.isEmpty { out.name = name }
        return out
    }

    /// Re-projects a typed policy into the dynamic form
    /// ``canonicalRoutePolicy(_:)`` reads, so that the one implementation of
    /// the defaulting rule serves both the import and the export path — which
    /// is the property app-store-ops.js §18 exists to have.
    private static func routePolicyJSON(_ policy: RoutePolicy?) -> JSON? {
        guard let policy else { return nil }
        var pairs: [(String, JSON)] = []
        if let mode = policy.mode { pairs.append(("mode", .string(mode))) }
        if let jrOnly = policy.jrOnly { pairs.append(("jr_only", .bool(jrOnly))) }
        if let value = policy.allowAlternatives { pairs.append(("allow_alternatives", .bool(value))) }
        if let value = policy.allowBrowserStraightLineFallback {
            pairs.append(("allow_browser_straight_line_fallback", .bool(value)))
        }
        if let codes = policy.allowedInstitutionTypeCodes {
            pairs.append(("allowed_institution_type_codes", .array(codes.map(JSON.string))))
        }
        if let names = policy.preferredLineNames {
            pairs.append(("preferred_line_names", .array(names.map(JSON.string))))
        }
        if let names = policy.preferredOperatorNames {
            pairs.append(("preferred_operator_names", .array(names.map(JSON.string))))
        }
        if let mode = policy.institutionFilterMode {
            pairs.append(("institution_filter_mode", .string(mode)))
        }
        return .object(JSON.Object(pairs))
    }

    // MARK: - makeUniqueTrainId

    /// `makeUniqueTrainId` — `odr_001`, then `odr_001-2`, `odr_001-3`, …
    ///
    /// jsonspec §3.2/§11.2: import always appends, so a colliding id is
    /// renamed rather than refused. A blank base becomes `"train"`.
    public static func makeUniqueTrainId(_ baseID: String?, existingIDs: Set<String>) -> String {
        let trimmed = jsTrim(baseID ?? "train")
        // `String(baseId || "train").trim() || "train"` — the second fallback
        // is what catches a base that was only whitespace.
        let cleanBase = trimmed.isEmpty ? "train" : trimmed
        var id = cleanBase
        var counter = 2
        while existingIDs.contains(id) {
            id = "\(cleanBase)-\(counter)"
            counter += 1
        }
        return id
    }
}

// MARK: - the dynamic JSON value

extension TrainValidation {

    /// A JSON value that keeps its object keys in JavaScript's own order.
    ///
    /// A `[String: JSON]` would be wrong twice over. Order first:
    /// ``assertOnlyKeys(_:_:_:)`` throws on the *first* unsupported key, so
    /// the order decides which key the error names, and a Swift dictionary
    /// has none. Equality second: `Dictionary` keys compare by canonical
    /// equivalence, so two keys JavaScript keeps apart would collide.
    public indirect enum JSON: Equatable, Sendable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSON])
        case object(Object)

        /// `===`, not Swift's `==`.
        ///
        /// Written out rather than synthesised so that two strings compare by
        /// UTF-16 code unit. Every `!==` in the validator that this stands in
        /// for compares against an ASCII literal today, but the values on the
        /// left are station names and imported text, and the day one of them
        /// arrives decomposed a synthesised `==` would start answering true
        /// where the app answers false.
        public static func == (lhs: JSON, rhs: JSON) -> Bool {
            switch (lhs, rhs) {
            case (.null, .null): true
            case let (.bool(a), .bool(b)): a == b
            // NaN is not equal to itself in JavaScript either, and `==` on
            // Double already agrees.
            case let (.number(a), .number(b)): a == b
            case let (.string(a), .string(b)): TrainValidation.jsStringEquals(a, b)
            case let (.array(a), .array(b)): a == b
            case let (.object(a), .object(b)): a == b
            default: false
            }
        }

        /// An insertion-ordered object with JavaScript's `OwnPropertyKeys`
        /// ordering already applied.
        public struct Object: Equatable, Sendable {
            /// Keys in `Object.keys` order — see ``init(_:)``.
            public private(set) var keys: [String]
            private var values: [JSON]

            /// Applies JavaScript's own key ordering: every **array-index**
            /// key first, in ascending numeric order, then all remaining keys
            /// in insertion order. That is why
            /// `{"zebra":1,"2":1,"10":1,"1":1}` reports `"1"` as its first
            /// key, not `"zebra"` and not `"10"`.
            ///
            /// A repeated key keeps the position of its first appearance and
            /// takes the value of its last, which is what `JSON.parse` does.
            public init(_ pairs: [(String, JSON)]) {
                var orderedKeys: [String] = []
                var orderedValues: [JSON] = []
                // A key index rather than the `firstIndex(where:)` scan this
                // replaced: that scan made building an object O(n²) in its
                // key count. `jsStringEquals` compares UTF-16 code units
                // (not Swift's canonically-equivalent `==`), so the index is
                // keyed on `[UInt16]`, the same comparison basis — same
                // winner for a duplicate key, same first-seen order.
                var indexOfKey: [[UInt16]: Int] = [:]
                for (key, value) in pairs {
                    let codeUnits = Array(key.utf16)
                    if let existing = indexOfKey[codeUnits] {
                        orderedValues[existing] = value
                    } else {
                        indexOfKey[codeUnits] = orderedKeys.count
                        orderedKeys.append(key)
                        orderedValues.append(value)
                    }
                }
                // A stable partition, so the non-index keys keep their order.
                let indexed = orderedKeys.indices.filter { Object.arrayIndex(orderedKeys[$0]) != nil }
                    .sorted { Object.arrayIndex(orderedKeys[$0])! < Object.arrayIndex(orderedKeys[$1])! }
                let rest = orderedKeys.indices.filter { Object.arrayIndex(orderedKeys[$0]) == nil }
                let order = indexed + rest
                keys = order.map { orderedKeys[$0] }
                values = order.map { orderedValues[$0] }
            }

            /// An "array index" in the ECMAScript sense: the canonical
            /// decimal spelling of an integer in 0…2³²−2. `"01"`, `"-1"` and
            /// `"1.0"` are ordinary string keys.
            private static func arrayIndex(_ key: String) -> UInt32? {
                let units = Array(key.utf16)
                guard !units.isEmpty, units.count <= 10,
                    units.allSatisfy({ $0 >= 48 && $0 <= 57 })
                else { return nil }
                if units.count > 1 && units[0] == 48 { return nil }  // no leading zero
                // An array index is 0 ≤ i < 2³²−1, so the largest one is 4294967294.
                guard let value = UInt32(key), value < UInt32.max else { return nil }
                return value
            }

            public subscript(key: String) -> JSON? {
                guard
                    let index = keys.firstIndex(where: { TrainValidation.jsStringEquals($0, key) })
                else { return nil }
                return values[index]
            }

            public static func == (lhs: Object, rhs: Object) -> Bool {
                lhs.keys.count == rhs.keys.count
                    && zip(lhs.keys, rhs.keys).allSatisfy(TrainValidation.jsStringEquals)
                    && lhs.values == rhs.values
            }
        }

        /// Property access. Non-objects have no properties, which is exactly
        /// what JavaScript reports for a number, a string or a boolean —
        /// `null` is the one that throws, and that is handled at the two call
        /// sites that reach it.
        public subscript(key: String) -> JSON? {
            guard case .object(let object) = self else { return nil }
            return object[key]
        }

        /// `Object.keys(value)` — empty for everything that is not an object.
        public var ownKeys: [String] {
            switch self {
            case .object(let object): object.keys
            // `Object.keys(["a","b"])` is ["0","1"], which is how an array
            // handed to assertOnlyKeys reports "0" as an unsupported field.
            case .array(let items): items.indices.map(String.init)
            default: []
            }
        }

        public func hasOwnKey(_ key: String) -> Bool {
            guard case .object(let object) = self else { return false }
            return object[key] != nil
        }

        /// JavaScript truthiness: `false`, `0`, `-0`, `NaN`, `""` and `null`
        /// are falsy, everything else — including `[]` and `{}` — is truthy.
        public var isTruthy: Bool {
            switch self {
            case .null: false
            case .bool(let value): value
            case .number(let value): !(value == 0 || value.isNaN)
            case .string(let value): !value.isEmpty
            case .array, .object: true
            }
        }

        public var isString: Bool { if case .string = self { return true } else { return false } }

        /// `value || []`, for the several places the JavaScript writes it.
        var orEmptyArray: JSON { isTruthy ? self : .array([]) }

        /// `value || null`, coerced to a string — the shape the code fields
        /// take (`section.from_n02_station_code || null`).
        var orNullString: String? { isTruthy ? TrainValidation.jsToString(self) : nil }

        /// The value as a string when it is a truthy string, else nil — the
        /// shape behind `x.name || fallback`.
        var stringOrNilIfFalsy: String? {
            if case .string(let value) = self, !value.isEmpty { return value }
            return nil
        }

        /// The value as a string when it *is* a string, else nil — the shape
        /// behind `typeof x === "string" ? … : …`, where an empty string is
        /// still a string.
        var stringOrNilIfNotString: String? {
            if case .string(let value) = self { return value }
            return nil
        }
    }

    /// ECMAScript `String(value)`.
    ///
    /// `JSNumber.string` rather than Swift's own `description`, because
    /// JavaScript prints an integral number without a fractional part — the
    /// number `123456` has to spell `"123456"` to be recognised as a
    /// six-digit station code, where `String(123456.0)` would give
    /// `"123456.0"` and it would not.
    static func jsToString(_ value: JSON) -> String {
        switch value {
        case .null: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): JSNumber.string(number)
        case .string(let text): text
        // Array#toString joins with "," and spells null/undefined as "".
        case .array(let items):
            items.map { $0 == .null ? "" : jsToString($0) }.joined(separator: ",")
        case .object: "[object Object]"
        }
    }
}

// MARK: - reading and writing JSON text

extension TrainValidation.JSON {

    /// `JSON.parse`, preserving key order.
    ///
    /// Hand-written rather than `JSONSerialization` because the order of an
    /// object's keys has to survive, and neither `JSONSerialization` nor
    /// `JSONDecoder` keeps it.
    public static func parse(_ text: String) throws -> TrainValidation.JSON {
        var parser = Parser(Array(text.utf8))
        let value = try parser.parseValue()
        try parser.skipWhitespace()
        guard parser.isAtEnd else { throw parser.error("Unexpected non-whitespace character after JSON") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var depth = 0

        /// How deeply nested an object/array structure this parser accepts.
        /// Guards the recursive-descent `parseValue`/`parseObject`/
        /// `parseArray` against a stack overflow on adversarial input
        /// (`"[[[[…"` thousands deep) by failing with the parser's ordinary
        /// syntax error instead of crashing.
        static let maxNestingDepth = 256

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var isAtEnd: Bool { index >= bytes.count }

        func error(_ message: String) -> TrainValidation.ValidationError {
            TrainValidation.ValidationError(
                kind: .syntaxError, message: "\(message) at position \(index)")
        }

        mutating func skipWhitespace() throws {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }

        mutating func parseValue() throws -> TrainValidation.JSON {
            try skipWhitespace()
            guard index < bytes.count else { throw error("Unexpected end of JSON input") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return .number(try parseNumber())
            }
        }

        mutating func expect(_ literal: String) throws {
            for byte in literal.utf8 {
                guard index < bytes.count, bytes[index] == byte else {
                    throw error("Unexpected token")
                }
                index += 1
            }
        }

        mutating func parseObject() throws -> TrainValidation.JSON {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Parser.maxNestingDepth else { throw error("JSON nested too deeply") }
            index += 1  // {
            var pairs: [(String, TrainValidation.JSON)] = []
            try skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(TrainValidation.JSON.Object(pairs))
            }
            while true {
                try skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw error("Expected property name or '}' in JSON")
                }
                let key = try parseString()
                try skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw error("Expected ':' after property name in JSON")
                }
                index += 1
                pairs.append((key, try parseValue()))
                try skipWhitespace()
                guard index < bytes.count else { throw error("Unexpected end of JSON input") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                if bytes[index] == UInt8(ascii: "}") {
                    index += 1
                    return .object(TrainValidation.JSON.Object(pairs))
                }
                throw error("Expected ',' or '}' after property value in JSON")
            }
        }

        mutating func parseArray() throws -> TrainValidation.JSON {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Parser.maxNestingDepth else { throw error("JSON nested too deeply") }
            index += 1  // [
            var items: [TrainValidation.JSON] = []
            try skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try parseValue())
                try skipWhitespace()
                guard index < bytes.count else { throw error("Unexpected end of JSON input") }
                if bytes[index] == UInt8(ascii: ",") {
                    index += 1
                    continue
                }
                if bytes[index] == UInt8(ascii: "]") {
                    index += 1
                    return .array(items)
                }
                throw error("Expected ',' or ']' after array element in JSON")
            }
        }

        mutating func parseString() throws -> String {
            index += 1  // opening quote
            var units: [UInt16] = []
            var literal: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    Self.flushStringLiteral(&literal, units: &units)
                    // A lone surrogate cannot live in a Swift String; JSON
                    // text produced by this project never contains one, and
                    // substituting U+FFFD is what String(decoding:) would do
                    // anyway.
                    return String(decoding: units, as: UTF16.self)
                }
                if byte == UInt8(ascii: "\\") {
                    Self.flushStringLiteral(&literal, units: &units)
                    units.append(try parseStringEscape())
                    continue
                }
                guard byte > 0x1F else {
                    throw error("Bad control character in string literal in JSON")
                }
                literal.append(byte)
                index += 1
            }
            throw error("Unterminated string in JSON")
        }

        private static func flushStringLiteral(_ literal: inout [UInt8], units: inout [UInt16]) {
            guard !literal.isEmpty else { return }
            units.append(contentsOf: Array(String(decoding: literal, as: UTF8.self).utf16))
            literal.removeAll(keepingCapacity: true)
        }

        private mutating func parseStringEscape() throws -> UInt16 {
            index += 1
            guard index < bytes.count else { throw error("Unexpected end of JSON input") }
            let escape = bytes[index]
            index += 1
            if escape == UInt8(ascii: "u") { return try parseUnicodeEscape() }
            if let unit = Self.simpleEscapeUnit(escape) { return unit }
            throw error("Bad escaped character in JSON")
        }

        private static func simpleEscapeUnit(_ escape: UInt8) -> UInt16? {
            switch escape {
            case UInt8(ascii: "\""): return 0x22
            case UInt8(ascii: "\\"): return 0x5C
            case UInt8(ascii: "/"): return 0x2F
            case UInt8(ascii: "b"): return 0x08
            case UInt8(ascii: "f"): return 0x0C
            case UInt8(ascii: "n"): return 0x0A
            case UInt8(ascii: "r"): return 0x0D
            case UInt8(ascii: "t"): return 0x09
            default: return nil
            }
        }

        private mutating func parseUnicodeEscape() throws -> UInt16 {
            guard index + 4 <= bytes.count else {
                throw error("Bad Unicode escape in JSON")
            }
            var unit: UInt16 = 0
            for offset in 0..<4 {
                let digit = bytes[index + offset]
                let value: UInt16
                switch digit {
                case 0x30...0x39: value = UInt16(digit - 0x30)
                case 0x41...0x46: value = UInt16(digit - 0x41 + 10)
                case 0x61...0x66: value = UInt16(digit - 0x61 + 10)
                default: throw error("Bad Unicode escape in JSON")
                }
                unit = unit << 4 | value
            }
            index += 4
            return unit
        }

        mutating func parseNumber() throws -> Double {
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }

            guard index < bytes.count else { throw error("Unexpected end of JSON input") }
            switch bytes[index] {
            case UInt8(ascii: "0"):
                index += 1
                guard index >= bytes.count || !(0x30...0x39).contains(bytes[index]) else {
                    throw error("Leading zero in JSON number")
                }
            case 0x31...0x39:
                repeat { index += 1 } while index < bytes.count
                    && (0x30...0x39).contains(bytes[index])
            default:
                throw error("Unexpected token")
            }

            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                    throw error("Expected digit after decimal point in JSON number")
                }
                repeat { index += 1 } while index < bytes.count
                    && (0x30...0x39).contains(bytes[index])
            }

            if index < bytes.count,
                bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E")
            {
                index += 1
                if index < bytes.count,
                    bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-")
                {
                    index += 1
                }
                guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                    throw error("Expected digit in exponent in JSON number")
                }
                repeat { index += 1 } while index < bytes.count
                    && (0x30...0x39).contains(bytes[index])
            }

            guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw error("Unexpected token")
            }
            return value
        }
    }

    /// `JSON.stringify` with the keys sorted — the canonical spelling both
    /// sides compare on.
    ///
    /// Sorted because Swift's `Codable` emits no defined key order, so a
    /// byte-for-byte round-trip check has to canonicalise one. The sort is
    /// JavaScript's own: `Array.prototype.sort` with no comparator compares
    /// by UTF-16 code unit, not by canonical equivalence.
    public var canonicalText: String {
        switch self {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let value): return JSNumber.string(value)
        case .string(let text):
            var out = ""
            CanonicalTrainStoreJSON.quote(text, into: &out)
            return out
        case .array(let items): return "[" + items.map(\.canonicalText).joined(separator: ",") + "]"
        case .object(let object):
            return "{"
                + object.keys
                .sorted { a, b in
                    // Strictly less by UTF-16 code unit: `a <= b && !(b <= a)`.
                    JSNumber.stringLessOrEqual(a, b) && !JSNumber.stringLessOrEqual(b, a)
                }
                .map { key in
                    var out = ""
                    CanonicalTrainStoreJSON.quote(key, into: &out)
                    return out + ":" + object[key]!.canonicalText
                }
                .joined(separator: ",") + "}"
        }
    }
}
