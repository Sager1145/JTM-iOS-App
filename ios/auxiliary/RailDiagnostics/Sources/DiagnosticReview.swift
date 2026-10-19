import Foundation

struct DiagnosticReviewNote: Codable, Identifiable {
    var id: String
    var conclusion: String
    var note: String
    var evidenceSHA256: [String: String]
}

struct DiagnosticReviewLedger: Codable {
    var schemaVersion = 1
    var requestID: String
    var dependencies: [String: String]
    var notes: [DiagnosticReviewNote]
}
