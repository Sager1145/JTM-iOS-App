import Foundation

// MARK: - RailTopologySolver: the attempt ladder
//
// The production solver does not ask the shortest-path question once. It builds a list of
// attempts from what the section and the trip say (`RouteSolver.buildSegmentRouteSolveAttempts`,
// `:1250-1325`) and takes the first attempt that gives a path passing its guards
// (`:3750-3860`). This is that ladder over `RailTopology.route`, with the same attempts in the
// same order. Lines and operators are identified by line id and operator name; the hints the
// solver derives from a section (explicit lines and operators, the lines and operators both
// ends have in common, preferred lines and operators) are inputs, computed by the caller.
//
// Attempts, per `RouteSolver`:
//  - explicit lines: those lines (with the explicit operators) under the home institution,
//    then softly; nothing else is tried;
//  - explicit operators only: the common lines under the operators (home, soft) when there
//    are common lines, then the operators alone (home, soft); nothing else is tried;
//  - otherwise: common lines and operators together, common lines, common operators (each
//    under the home institution, when the set is non-empty), then the soft hints under the
//    home institution, the common lines softly, a soft attempt, and finally the institution
//    only with no line or operator preference;
//  - when no attempt found a proven path and the institution mode is soft: one more attempt
//    with the explicit lines and operators kept, no preference and every institution allowed.
// "Home institution" is a hard filter to the allowed codes; "soft" is the preference penalty.
// In hard mode the filter is hard in every attempt and there is no penalty.
// The first path the same-name guard rejected is returned, `unproven`, when nothing else is found.

extension RailTopology {
    /// What the ladder is given for one section.
    public struct SectionPlan: Sendable {
        public var from: [NodeRef]
        public var to: [NodeRef]
        public var day: UInt32?
        /// The section's own lines and operators: user intent, never dropped.
        public var explicitLineIDs: Set<String>
        public var explicitOperators: Set<String>
        /// Lines and operators that both ends belong to.
        public var commonLineIDs: Set<String>
        public var commonOperators: Set<String>
        /// Soft preferences (the trip's and the section's lines and operators).
        public var preferredLineIDs: Set<String>
        public var preferredOperators: Set<String>
        /// The institution codes the trip allows (default: all five).
        public var allowedInstitutions: Set<UInt16>
        /// The trip's institution filter mode is "hard".
        public var hardInstitutionMode: Bool
        public var excludedInstitutions: Set<UInt16>
        public var fromNameOnly: Bool
        public var toNameOnly: Bool

        public static let allInstitutions: Set<UInt16> = [1, 2, 3, 4, 5]

        public init(from: [NodeRef], to: [NodeRef], day: UInt32? = nil,
                    explicitLineIDs: Set<String> = [], explicitOperators: Set<String> = [],
                    commonLineIDs: Set<String> = [], commonOperators: Set<String> = [],
                    preferredLineIDs: Set<String> = [], preferredOperators: Set<String> = [],
                    allowedInstitutions: Set<UInt16> = SectionPlan.allInstitutions,
                    hardInstitutionMode: Bool = false, excludedInstitutions: Set<UInt16> = [],
                    fromNameOnly: Bool = false, toNameOnly: Bool = false) {
            self.from = from; self.to = to; self.day = day
            self.explicitLineIDs = explicitLineIDs; self.explicitOperators = explicitOperators
            self.commonLineIDs = commonLineIDs; self.commonOperators = commonOperators
            self.preferredLineIDs = preferredLineIDs; self.preferredOperators = preferredOperators
            self.allowedInstitutions = allowedInstitutions; self.hardInstitutionMode = hardInstitutionMode
            self.excludedInstitutions = excludedInstitutions
            self.fromNameOnly = fromNameOnly; self.toNameOnly = toNameOnly
        }
    }

    /// One rung: required lines and operators, whether the home institution is a hard filter,
    /// and the preferences (nil: the plan's).
    struct Attempt: Equatable {
        var name: String
        var lines: Set<String>
        var operators: Set<String>
        var home: Bool
        var clearsPreferences = false
    }

    /// The solver's attempts for a plan, in order (`buildSegmentRouteSolveAttempts`).
    static func attempts(for plan: SectionPlan) -> [Attempt] {
        var list: [Attempt] = []
        func add(_ name: String, _ lines: Set<String>, _ operators: Set<String>, home: Bool, clears: Bool = false) {
            list.append(Attempt(name: name, lines: lines, operators: operators, home: home, clearsPreferences: clears))
        }
        if !plan.explicitLineIDs.isEmpty {
            add("explicit lines, home institution", plan.explicitLineIDs, plan.explicitOperators, home: true)
            add("explicit lines, soft institution", plan.explicitLineIDs, plan.explicitOperators, home: false)
            return list
        }
        if !plan.explicitOperators.isEmpty {
            if !plan.commonLineIDs.isEmpty {
                add("common lines under explicit operators, home institution", plan.commonLineIDs, plan.explicitOperators, home: true)
                add("common lines under explicit operators, soft institution", plan.commonLineIDs, plan.explicitOperators, home: false)
            }
            add("explicit operators, home institution", [], plan.explicitOperators, home: true)
            add("explicit operators, soft institution", [], plan.explicitOperators, home: false)
            return list
        }
        if !plan.commonLineIDs.isEmpty, !plan.commonOperators.isEmpty {
            add("common lines and operators, home institution", plan.commonLineIDs, plan.commonOperators, home: true)
        }
        if !plan.commonLineIDs.isEmpty { add("common lines, home institution", plan.commonLineIDs, [], home: true) }
        if !plan.commonOperators.isEmpty { add("common operators, home institution", [], plan.commonOperators, home: true) }
        add("home institution, soft line and operator hints", [], [], home: true)
        if !plan.commonLineIDs.isEmpty { add("common lines, other operators", plan.commonLineIDs, [], home: false) }
        add("soft fallback", [], [], home: false)
        add("institution only, unbiased", [], [], home: true, clears: true)
        return list
    }

    func query(for attempt: Attempt, in plan: SectionPlan) -> SectionQuery {
        var query = SectionQuery(from: plan.from, to: plan.to, day: plan.day,
                                 lineIDs: attempt.lines, operators: attempt.operators,
                                 excludedInstitutions: plan.excludedInstitutions,
                                 fromNameOnly: plan.fromNameOnly, toNameOnly: plan.toNameOnly)
        if !attempt.clearsPreferences {
            query.preferredLineIDs = plan.preferredLineIDs
            query.preferredOperators = plan.preferredOperators
        }
        if plan.hardInstitutionMode || attempt.home { query.institutions = plan.allowedInstitutions }
        else { query.preferredInstitutions = plan.allowedInstitutions }
        return query
    }

    /// Solves a section the way the production solver does: the first attempt with a proven
    /// path wins; when none has one and the mode is soft, the unpenalised attempt; otherwise
    /// the first guard-rejected path as `unproven`, or nil.
    public func solve(_ plan: SectionPlan, includeWithheld: Bool = false) -> SectionPath? {
        var guarded: SectionPath?
        for attempt in Self.attempts(for: plan) {
            guard let path = route(query(for: attempt, in: plan), includeWithheld: includeWithheld) else { continue }
            if !path.unproven { return path }
            if guarded == nil { guarded = path }
        }
        if !plan.hardInstitutionMode {
            let fallback = Attempt(name: "institution unpenalised soft fallback", lines: plan.explicitLineIDs,
                                   operators: plan.explicitOperators, home: false, clearsPreferences: true)
            var relaxed = plan
            relaxed.allowedInstitutions = SectionPlan.allInstitutions
            if let path = route(query(for: fallback, in: relaxed), includeWithheld: includeWithheld) {
                if !path.unproven { return path }
                if guarded == nil { guarded = path }
            }
        }
        return guarded
    }
}
