import Observation
import SwiftUI

@MainActor @Observable
final class DiagnosticTaskCommandBridge {
    var canCreate = true
    var canRun = false
    var canPause = false
    var canSwitch = true
    var canUseWorkspaceCommands = true
    var canPreviousCapture = false
    var canNextCapture = false
    @ObservationIgnored var newTask: (() -> Void)?
    @ObservationIgnored var openTask: (() -> Void)?
    @ObservationIgnored var runTask: (() -> Void)?
    @ObservationIgnored var pauseTask: (() -> Void)?
    @ObservationIgnored var switchWorkspace: ((Int) -> Void)?
    @ObservationIgnored var moveCapture: ((Int) -> Void)?
}
private struct DiagnosticTaskCommandKey: FocusedValueKey { typealias Value = DiagnosticTaskCommandBridge }
extension FocusedValues {
    var diagnosticTaskCommands: DiagnosticTaskCommandBridge? {
        get { self[DiagnosticTaskCommandKey.self] }
        set { self[DiagnosticTaskCommandKey.self] = newValue }
    }
}
