import Foundation
import Testing
@testable import RailInspection

struct RailwayEvidenceRootTests {
    @Test func externalArchiveOwnsBothAuxiliaryDefaults() throws {
        let root = RailwayEvidenceRoot.resolve(environment: [:], sourceFile: "/unrelated/checkout/ios/Source.swift")
        #expect(root.path == "/Volumes/JTM Evidence/99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local")
        #expect(RailwayEvidenceRoot.diagnosticSessions(root: root) == root.appendingPathComponent("diagnostics/sessions", isDirectory: true))
        #expect(RailwayEvidenceRoot.alignmentInspector(root: root) == root.appendingPathComponent("alignment-inspector", isDirectory: true))
        #expect(RailwayEvidenceRoot.batchEvidence(root: root) == root.appendingPathComponent("alignment-inspector/BatchEvidence", isDirectory: true))
    }

    @Test func explicitScratchRootDoesNotChangeImmutableRequestPaths() throws {
        let root = RailwayEvidenceRoot.resolve(environment: ["RAILWAY_EVIDENCE_ROOT": "/private/tmp/custom-evidence"], sourceFile: "/no/checkout/Source.swift")
        #expect(root.path == "/private/tmp/custom-evidence")
        #expect(try RailwayEvidenceRoot.validatedWriteURL(root, externalVolumeAvailable: false).path == root.resolvingSymlinksInPath().standardizedFileURL.path)
        let request = DiagnosticRequest(requestID: "legacy", workspace: .alignment, action: .prepare,
                                        sessionDirectory: "/private/tmp/retained-immutable-session", lineID: "own-line")
        let decoded = try JSONDecoder().decode(DiagnosticRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.sessionDirectory == "/private/tmp/retained-immutable-session")
        #expect(decoded == request)
    }

    @Test func unmountedArchiveAndInternalCheckoutCannotReceiveNewEvidence() {
        #expect(throws: Error.self) {
            try RailwayEvidenceRoot.validatedWriteURL(RailwayEvidenceRoot.resolve(environment: [:]), externalVolumeAvailable: false)
        }
        #expect(throws: Error.self) {
            try RailwayEvidenceRoot.validatedWriteURL(URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/GitHub/JTM-iOS-App/railway-evidence/local/__unmigrated-new-evidence"))
        }
    }

    @Test func writePathsResolveAliasesAndRejectEscapes() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("reviews.json")
        try Data("{}".utf8).write(to: target)
        let alias = root.appendingPathComponent("alias.json")
        try manager.createSymbolicLink(at: alias, withDestinationURL: target)
        #expect(try RailwayEvidenceRoot.validatedWriteURL(alias).path == target.resolvingSymlinksInPath().path)
        let escape = root.appendingPathComponent("escape")
        try manager.createSymbolicLink(at: escape, withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents"))
        #expect(throws: Error.self) {
            try RailwayEvidenceRoot.validatedWriteURL(escape.appendingPathComponent("new-evidence"))
        }
    }
}
