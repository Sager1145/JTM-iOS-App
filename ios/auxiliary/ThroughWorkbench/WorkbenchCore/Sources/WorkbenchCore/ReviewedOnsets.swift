import Foundation

extension WorkbenchDocument {
    /// Earliest-possible constraints supported by official onset announcements.
    /// These do not certify unchanged endpoint variants or national historical completeness.
    public static func reviewedOnsetPatches() throws -> [TemporalPatch] {
        guard let url = Bundle.module.url(forResource: "reviewed-onset-patches", withExtension: "json") else {
            throw WorkbenchError.invalid("缺少已核对的开始日期修复资源。")
        }
        return try JSONDecoder().decode([TemporalPatch].self, from: Data(contentsOf: url))
    }
}
