import SwiftUI

/// Catalyst reliably exposes one contextual diagnostic menu. Share the original
/// action views so standalone and unified keyboard behavior cannot drift.
struct UnifiedDiagnosticCommands: Commands {
    @FocusedValue(\.diagnosticTaskCommands) private var task
    @FocusedValue(\.inspectorCommands) private var alignment
    @FocusedValue(\.routeWorkbenchCommands) private var route
    @FocusedValue(\.throughWorkbenchCommands) private var through

    var body: some Commands {
        CommandMenu("Diagnostics") {
            Button("New diagnostic task") { task?.newTask?() }
                .keyboardShortcut("n", modifiers: [.command, .control]).disabled(task?.canCreate != true)
            Button("Open task request…") { task?.openTask?() }
                .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(task?.canCreate != true)
            Button("Run / resume task") { task?.runTask?() }
                .keyboardShortcut(.return, modifiers: .command).disabled(task?.canRun != true)
            Button("Pause current operation") { task?.pauseTask?() }
                .keyboardShortcut(.escape, modifiers: []).disabled(task?.canPause != true)
            Divider()
            ForEach(Array(DiagnosticWorkspace.allCases.enumerated()), id: \.element.id) { index, workspace in
                Button(workspace.rawValue) { task?.switchWorkspace?(index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
                    .disabled(task?.canSwitch != true)
            }
            Divider()
            Button("Previous captured view") { task?.moveCapture?(-1) }
                .keyboardShortcut("j", modifiers: [.control, .command])
                .disabled(task?.canUseWorkspaceCommands != true || task?.canPreviousCapture != true)
            Button("Next captured view") { task?.moveCapture?(1) }
                .keyboardShortcut("k", modifiers: [.control, .command])
                .disabled(task?.canUseWorkspaceCommands != true || task?.canNextCapture != true)
            Divider()
            Group {
                if let alignment {
                    InspectorCommandItems(bridge: alignment)
                } else if let route {
                    Button("Import journeys JSON") { route.open?() }
                        .keyboardShortcut("o", modifiers: .command).disabled(!route.canOpen)
                    Divider()
                    RouteWorkbenchCommandItems(bridge: route)
                } else if let through {
                    Button("Import working document") { through.open?() }
                        .keyboardShortcut("o", modifiers: .command).disabled(!through.canOpen)
                    Divider()
                    ThroughWorkbenchCommandItems(bridge: through)
                } else {
                    Text("Select an inspection workspace")
                }
            }.disabled(task?.canUseWorkspaceCommands != true)
        }
    }
}
