import Foundation

/// Captures package-load context before a diagnostic persists localizedDescription.
/// Only immutable text crosses the detached task boundary; NSError/userInfo do not.
public struct DiagnosticInputReadError: LocalizedError, Sendable {
    private let message: String

    public init(requestedURL: URL, underlying error: any Error) {
        var details = ["Package input read failed: \(requestedURL.path)"]
        var cause: NSError? = error as NSError
        var visited = Set<ObjectIdentifier>()
        while let current = cause {
            guard visited.insert(ObjectIdentifier(current)).inserted else {
                details.append("Underlying error chain repeats a previously reported cause.")
                break
            }
            details.append("\(current.domain) code=\(current.code): \(current.localizedDescription)")
            cause = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        message = details.joined(separator: "\nCaused by: ")
    }

    public var errorDescription: String? { message }
}
