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

    // MARK: Map taps while a card is open

    private static func answer(
        _ tap: MapTapKind, _ host: WorkspaceSurfaceHost?, lease: Bool, preview: Bool, editor: Bool,
        nested: Bool = false
    ) -> MapTapCardAnswer {
        WorkspaceSurfacePolicy.mapTapAnswer(
            tap, cardHost: host, leaseHeld: lease, linePreviewShown: preview, editorOpen: editor,
            nestedSurfaceUp: nested)
    }

    @Test("Map tap table: every tap, host, lease, preview and editor state")
    func mapTapTable() {
        let hosts: [WorkspaceSurfaceHost?] = [nil, .panel, .systemSheet, .fullWindowCover, .dialog]
        for tap in MapTapKind.allCases {
            for host in hosts {
                for lease in [false, true] {
                    for preview in [false, true] {
                        for editor in [false, true] {
                            let expected: MapTapCardAnswer
                            if editor, tap == .station || tap == .lines {
                                expected = .blocked
                            } else if host == .panel {
                                expected = tap == .empty ? (editor ? .blocked : .clearSelectionAndCloseCard) : .proceed
                            } else {
                                switch tap {
                                case .station: expected = lease ? .blocked : .proceed
                                case .lines: expected = lease || preview ? .blocked : .proceed
                                case .trips: expected = preview ? .blocked : .proceed
                                case .empty: expected = preview || lease ? .blocked : .clearSelection
                                }
                            }
                            #expect(
                                Self.answer(tap, host, lease: lease, preview: preview, editor: editor)
                                    == expected,
                                "\(tap) host=\(String(describing: host)) lease=\(lease) preview=\(preview) editor=\(editor)")
                        }
                    }
                }
            }
        }
    }

    @Test("Map tap: the panel keeps answering a station, line or trip tap over a trip card")
    func panelTapsProceedOverLease() {
        for tap in [MapTapKind.station, .lines, .trips] {
            #expect(Self.answer(tap, .panel, lease: true, preview: true, editor: false) == .proceed)
        }
        #expect(Self.answer(.empty, .panel, lease: true, preview: true, editor: false)
            == .clearSelectionAndCloseCard)
    }

    @Test("Map tap: a nested panel surface keeps every tap from closing or replacing the card")
    func panelNestedSurfaceBlocksTaps() {
        for tap in MapTapKind.allCases {
            for lease in [false, true] {
                #expect(Self.answer(tap, .panel, lease: lease, preview: false, editor: false, nested: true)
                    == .blocked, "nested \(tap)")
            }
        }
        // Outside the panel the nested flag changes nothing.
        #expect(Self.answer(.empty, .systemSheet, lease: false, preview: false, editor: false, nested: true)
            == .clearSelection)
    }
}
