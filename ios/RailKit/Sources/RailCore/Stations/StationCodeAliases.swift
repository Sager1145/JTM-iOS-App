import Foundation

/// Maps a legacy platform station code to the current per-region grammar.
///
/// Hong Kong and Macao station codes used to embed the *line*, so one station
/// carried a different code on every line through it (金鐘: `SIL-MTR-ADM`,
/// `ISL-MTR-ADM`, `EAL-LOW-MTR-ADM` …). They are now `{OPERATOR}-{STOP}`, the
/// same on every line, like Japan and Taiwan. Persisted rides still carry the
/// old shapes in `n02_station_code`, so the mapping is applied where a stop is
/// decoded and where a code is looked up; the ride re-saves with the new code.
///
/// - `EAL-LOW-MTR-ADM` → `MTR-ADM`
/// - `LR-505-LR-100` → `LR-100`
/// - `MLM-TAIPA-MLM-BARRA` → `MLM-BARRA`
/// - `TRAM-HV-105` → `TRAM-105`
/// - `KLRT-NETWORK-C1` → `KLRT-C1` (Taiwan's Kaohsiung LRT dropped its
///   `NETWORK` segment in the same pass)
///
/// Japanese six-digit codes, Taiwanese `OP-ID` codes, already-canonical codes
/// and the empty string pass through unchanged. See
/// `docs/decisions/0010-unified-station-tables.md`.
public enum StationCodeAliases {
    private static let lineEmbeddingOperators: Set<String> = ["MTR", "LR", "MLM"]

    public static func canonical(_ code: String) -> String {
        let segments = code.split(separator: "-", omittingEmptySubsequences: false)
        guard segments.count >= 3, let last = segments.last else { return code }
        let secondLast = segments[segments.count - 2]
        if lineEmbeddingOperators.contains(String(secondLast)) {
            return "\(secondLast)-\(last)"
        }
        if segments[0] == "TRAM" {
            return "TRAM-\(last)"
        }
        if segments[1] == "NETWORK" {
            var kept = segments
            kept.remove(at: 1)
            return kept.joined(separator: "-")
        }
        return code
    }
}
