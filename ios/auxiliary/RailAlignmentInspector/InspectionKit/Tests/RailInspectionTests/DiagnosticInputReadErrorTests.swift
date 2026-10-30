import Foundation
import Testing
@testable import RailInspection

struct DiagnosticInputReadErrorTests {
    // Regression: persisting only localizedDescription loses exact input and cause codes.
    private func persistedMessage(_ error: any Error, requestedURL: URL) -> String {
        DiagnosticInputReadError(requestedURL: requestedURL, underlying: error).localizedDescription
    }

    @Test func missingFileReadRetainsExactInputAndRealCause() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostic-missing-\(UUID().uuidString)")
            .appendingPathComponent("candidate with spaces/jp-2025.json")
        do {
            _ = try Data(contentsOf: url)
            Issue.record("The deliberately absent input unexpectedly exists")
        } catch {
            let message = persistedMessage(error, requestedURL: url)
            #expect(message.contains(url.path))
            #expect(message.contains("NSCocoaErrorDomain code=260"))
            #expect(message.contains("NSPOSIXErrorDomain code=2"))
            let saved = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(String.self, from: saved) == message)
        }
    }

    @Test func permissionCauseChainSurvivesLocalizedMessagePersistence() {
        let url = URL(fileURLWithPath: "/exact candidate/queue-103/jp-2025.json")
        let posix = NSError(domain: NSPOSIXErrorDomain, code: 13,
                            userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        let provider = NSError(domain: "DiagnosticProvider", code: 41,
                               userInfo: [NSUnderlyingErrorKey: posix])
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: 257,
                            userInfo: [NSLocalizedDescriptionKey: "The file couldn’t be opened.",
                                       NSUnderlyingErrorKey: provider])
        let message = persistedMessage(cocoa, requestedURL: url)
        #expect(message.contains(url.path))
        #expect(message.contains("NSCocoaErrorDomain code=257"))
        #expect(message.contains("DiagnosticProvider code=41"))
        #expect(message.contains("NSPOSIXErrorDomain code=13"))
        #expect(message.contains("Permission denied"))
    }
}
