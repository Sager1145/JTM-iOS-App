import RailPresentation
import Testing

struct WorkspaceSurfacePolicyTests {
    private static let modes: [WorkspaceLayoutMode] = [.compactOverlay, .sideBySide]

    /// The map-covering popups the docked panel absorbs.
    private static let absorbed: [WorkspaceSurfaceKind] = [
        .tripCard, .tripDetails, .stationCard, .lineCard, .overlappingTripsChooser,
        .lineChooser, .tripNoteRead, .tripNoteForm, .groupPicker,
    ]

    @Test("Every kind has the intended host in every mode")
    func everyKindEveryMode() {
        for mode in Self.modes {
            for kind in WorkspaceSurfaceKind.allCases {
                let expected: WorkspaceSurfaceHost
                switch kind {
                case .shareComposer: expected = .fullWindowCover
                case .deleteConfirmation: expected = .dialog
                case .journeyEditor: expected = .panel
                case .tripCard, .tripDetails, .stationCard, .lineCard,
                    .overlappingTripsChooser, .lineChooser, .tripNoteRead,
                    .tripNoteForm, .groupPicker:
                    expected = mode == .sideBySide ? .panel : .systemSheet
                }
                #expect(
                    WorkspaceSurfacePolicy.host(for: kind, mode: mode) == expected,
                    "\(kind) in \(mode)")
            }
        }
    }

    @Test("Docked layout hosts every absorbed popup in the panel")
    func dockedUsesPanel() {
        for kind in Self.absorbed {
            #expect(WorkspaceSurfacePolicy.host(for: kind, mode: .sideBySide) == .panel)
        }
    }

    @Test("Compact phone layout keeps system sheets")
    func compactUnchanged() {
        for kind in Self.absorbed {
            #expect(WorkspaceSurfacePolicy.host(for: kind, mode: .compactOverlay) == .systemSheet)
        }
    }

    @Test("Share composer and delete confirmation never move into the panel")
    func fixedHosts() {
        for mode in Self.modes {
            #expect(WorkspaceSurfacePolicy.host(for: .shareComposer, mode: mode) == .fullWindowCover)
            #expect(WorkspaceSurfacePolicy.host(for: .deleteConfirmation, mode: mode) == .dialog)
        }
    }

    @Test("Tabs hide exactly when the surface fills the panel")
    func tabsHideIffPanel() {
        for mode in Self.modes {
            for kind in WorkspaceSurfaceKind.allCases {
                #expect(
                    WorkspaceSurfacePolicy.hidesTabsWhilePresented(kind: kind, mode: mode)
                        == (WorkspaceSurfacePolicy.host(for: kind, mode: mode) == .panel))
            }
        }
        #expect(WorkspaceSurfacePolicy.hidesTabsWhilePresented(kind: .tripCard, mode: .sideBySide))
        #expect(!WorkspaceSurfacePolicy.hidesTabsWhilePresented(kind: .tripCard, mode: .compactOverlay))
        #expect(WorkspaceSurfacePolicy.hidesTabsWhilePresented(kind: .journeyEditor, mode: .compactOverlay))
    }

    @Test("Map obstruction is constant only when docked")
    func obstruction() {
        #expect(WorkspaceSurfacePolicy.keepsMapObstructionConstant(mode: .sideBySide))
        #expect(!WorkspaceSurfacePolicy.keepsMapObstructionConstant(mode: .compactOverlay))
    }

    @Test("Mac Catalyst is always docked, so every absorbed popup is panel-hosted")
    func macCatalyst() {
        let mode = WorkspaceLayoutPolicy(width: 300, height: 300, isMacCatalyst: true).mode
        #expect(mode == .sideBySide)
        for kind in Self.absorbed {
            #expect(WorkspaceSurfacePolicy.host(for: kind, mode: mode) == .panel)
        }
    }

    @Test("Nested panel surfaces stay in the panel with a back step")
    func nestedInPanel() {
        for (child, parent) in [
            (WorkspaceSurfaceKind.tripDetails, WorkspaceSurfaceKind.tripCard),
            (.lineCard, .stationCard), (.tripNoteRead, .tripCard),
            (.tripNoteForm, .tripNoteRead), (.groupPicker, .tripCard),
        ] {
            let docked = WorkspaceSurfacePolicy.nestedHost(
                child: child, from: parent, mode: .sideBySide)
            #expect(docked == WorkspaceNestedSurface(host: .panel, hasBackStep: true))
            let compact = WorkspaceSurfacePolicy.nestedHost(
                child: child, from: parent, mode: .compactOverlay)
            #expect(compact == WorkspaceNestedSurface(host: .systemSheet, hasBackStep: false))
        }
    }

    @Test("Nested non-panel children follow their own host with no back step")
    func nestedNonPanel() {
        for mode in Self.modes {
            for parent in WorkspaceSurfaceKind.allCases {
                for child in [WorkspaceSurfaceKind.shareComposer, .deleteConfirmation] {
                    let nested = WorkspaceSurfacePolicy.nestedHost(
                        child: child, from: parent, mode: mode)
                    #expect(nested.host == WorkspaceSurfacePolicy.host(for: child, mode: mode))
                    #expect(!nested.hasBackStep)
                }
            }
        }
    }

    @Test("A back step exists only for panel-to-panel nesting, for every pair")
    func nestedExhaustive() {
        for mode in Self.modes {
            for parent in WorkspaceSurfaceKind.allCases {
                for child in WorkspaceSurfaceKind.allCases {
                    let nested = WorkspaceSurfacePolicy.nestedHost(
                        child: child, from: parent, mode: mode)
                    let both = WorkspaceSurfacePolicy.host(for: child, mode: mode) == .panel
                        && WorkspaceSurfacePolicy.host(for: parent, mode: mode) == .panel
                    #expect(nested.hasBackStep == both)
                }
            }
        }
    }
}
