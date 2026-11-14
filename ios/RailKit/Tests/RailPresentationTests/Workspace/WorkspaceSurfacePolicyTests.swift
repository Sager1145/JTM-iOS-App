import RailPresentation
import Testing

struct WorkspaceSurfacePolicyTests {
    private static let modes: [WorkspaceLayoutMode] = [.compactOverlay, .sideBySide]

    /// The map-covering popups the docked panel absorbs.
    private static let absorbed: [WorkspaceSurfaceKind] = [
        .tripCard, .tripDetails, .stationCard, .lineCard, .overlappingTripsChooser,
        .lineChooser, .tripNoteRead, .tripNoteForm, .groupPicker,
    ]

    private static func host(
        _ kind: WorkspaceSurfaceKind, _ mode: WorkspaceLayoutMode, hinged: Bool = false
    ) -> WorkspaceSurfaceHost {
        WorkspaceSurfacePolicy.host(for: kind, mode: mode, isHinged: hinged)
    }

    @Test("Literal decision table: absorbed kinds by layout")
    func literalTable() {
        // (mode, hinged, expected host for every absorbed kind)
        let rows: [(WorkspaceLayoutMode, Bool, WorkspaceSurfaceHost)] = [
            (.compactOverlay, false, .systemSheet),
            (.sideBySide, false, .panel),
            (.compactOverlay, true, .systemSheet),
            (.sideBySide, true, .systemSheet),
        ]
        for (mode, hinged, expected) in rows {
            for kind in Self.absorbed {
                #expect(Self.host(kind, mode, hinged: hinged) == expected, "\(kind) \(mode) hinged=\(hinged)")
            }
        }
    }

    @Test("Literal decision table: fixed kinds in every layout")
    func literalFixed() {
        for mode in Self.modes {
            for hinged in [false, true] {
                #expect(Self.host(.shareComposer, mode, hinged: hinged) == .fullWindowCover)
                #expect(Self.host(.deleteConfirmation, mode, hinged: hinged) == .dialog)
                #expect(Self.host(.journeyEditor, mode, hinged: hinged) == .panel)
            }
        }
    }

    @Test("Every kind is covered by the table (absorbed or fixed)")
    func allKindsClassified() {
        let fixed: [WorkspaceSurfaceKind] = [.shareComposer, .deleteConfirmation, .journeyEditor]
        for kind in WorkspaceSurfaceKind.allCases {
            #expect(Self.absorbed.contains(kind) != fixed.contains(kind), "\(kind)")
        }
    }

    @Test("Hinged layout never uses the panel for absorbed popups, even when width says sideBySide")
    func hingedKeepsSheets() {
        for kind in Self.absorbed {
            #expect(Self.host(kind, .sideBySide, hinged: true) != .panel)
            #expect(!WorkspaceSurfacePolicy.hidesTabsWhilePresented(
                kind: kind, mode: .sideBySide, isHinged: true))
        }
    }

    @Test("Tabs hide only for panel-hosted surfaces")
    func tabsHide() {
        let hides = WorkspaceSurfacePolicy.hidesTabsWhilePresented
        #expect(hides(.tripCard, .sideBySide, false))
        #expect(!hides(.tripCard, .compactOverlay, false))
        #expect(!hides(.tripCard, .sideBySide, true))
        #expect(hides(.journeyEditor, .compactOverlay, false))
        #expect(!hides(.shareComposer, .sideBySide, false))
        #expect(!hides(.deleteConfirmation, .sideBySide, false))
    }

    @Test("Map obstruction is constant only when docked and not hinged")
    func obstruction() {
        let keeps = WorkspaceSurfacePolicy.keepsMapObstructionConstant
        #expect(keeps(.sideBySide, false))
        #expect(!keeps(.compactOverlay, false))
        #expect(!keeps(.sideBySide, true))
        #expect(!keeps(.compactOverlay, true))
    }

    @Test("Mac Catalyst is always docked, so every absorbed popup is panel-hosted")
    func macCatalyst() {
        let mode = WorkspaceLayoutPolicy(width: 300, height: 300, isMacCatalyst: true).mode
        #expect(mode == .sideBySide)
        for kind in Self.absorbed {
            #expect(Self.host(kind, mode) == .panel)
        }
    }

    @Test("Nested panel surfaces stay in the panel with a back step")
    func nestedInPanel() {
        for (child, parent) in [
            (WorkspaceSurfaceKind.tripDetails, WorkspaceSurfaceKind.tripCard),
            (.lineCard, .stationCard), (.tripNoteRead, .tripCard),
            (.tripNoteForm, .tripNoteRead),
        ] {
            let docked = WorkspaceSurfacePolicy.nestedHost(
                child: child, from: parent, mode: .sideBySide, isHinged: false)
            #expect(docked == WorkspaceNestedSurface(host: .panel, hasBackStep: true))
            for (mode, hinged) in [(WorkspaceLayoutMode.compactOverlay, false), (.sideBySide, true)] {
                let sheet = WorkspaceSurfacePolicy.nestedHost(
                    child: child, from: parent, mode: mode, isHinged: hinged)
                #expect(sheet == WorkspaceNestedSurface(host: .systemSheet, hasBackStep: false))
            }
        }
    }

    @Test("Group picker opens from a list row, so it is a panel surface with no parent step")
    func groupPickerFromList() {
        #expect(Self.host(.groupPicker, .sideBySide) == .panel)
        #expect(Self.host(.groupPicker, .compactOverlay) == .systemSheet)
    }

    @Test("Journey editor replaces its parent: no back step, parent dismissed")
    func journeyEditorReplaces() {
        for mode in Self.modes {
            for hinged in [false, true] {
                for parent in [WorkspaceSurfaceKind.tripDetails, .tripCard] {
                    let nested = WorkspaceSurfacePolicy.nestedHost(
                        child: .journeyEditor, from: parent, mode: mode, isHinged: hinged)
                    #expect(nested == WorkspaceNestedSurface(
                        host: .panel, hasBackStep: false, dismissesParent: true))
                }
            }
        }
    }

    @Test("Nested non-panel children follow their own host with no back step")
    func nestedNonPanel() {
        for mode in Self.modes {
            for hinged in [false, true] {
                for parent in WorkspaceSurfaceKind.allCases {
                    for child in [WorkspaceSurfaceKind.shareComposer, .deleteConfirmation] {
                        let nested = WorkspaceSurfacePolicy.nestedHost(
                            child: child, from: parent, mode: mode, isHinged: hinged)
                        #expect(nested.host == Self.host(child, mode, hinged: hinged))
                        #expect(!nested.hasBackStep)
                        #expect(!nested.dismissesParent)
                    }
                }
            }
        }
    }
}
