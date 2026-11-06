import CryptoKit
import Foundation

/// Bundled example rides carry user-style ids (`journey_` + 32 uppercase hex),
/// derived from their former descriptive ids as the first 16 bytes of
/// SHA-256 of that id. The port fixtures were generated before the change and
/// still name rides by the descriptive id; this maps such a name onto the id in
/// the bundled stores. An id already in the new form is returned unchanged.
enum SampleRideID {
    static func current(_ id: String) -> String {
        guard !id.hasPrefix("journey_") else { return id }
        let digest = SHA256.hash(data: Data(id.utf8))
        return "journey_" + digest.prefix(16).map { String(format: "%02X", $0) }.joined()
    }
}
