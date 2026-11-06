import Foundation

/// A scratch copy of only the files a patch stack touches, with every op
/// applied (report-only ops included, so a preview shows their effect).
/// The overlay is a pure function of (repository, patch stack): undoing a
/// patch is popping it and materialising again.
public enum ScratchOverlay {
    /// Rebuilds `directory` from the repository and `patches` and returns a
    /// root that reads patched files from it. Only AreaKit-owned paths under
    /// `directory` (the repository-relative data paths) are replaced.
    @discardableResult
    public static func materialize(repo: URL, patches: [AreaPatch], into directory: URL) throws -> DataRoot {
        let fm = FileManager.default
        for file in DataFile.allCases {
            let target = directory.appending(path: file.relativePath)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        }
        let ops = patches.flatMap(\.ops)
        for file in DataFile.allCases {
            let fileOps = ops.filter { $0.op.file == file }
            guard !fileOps.isEmpty else { continue }
            let original = try Data(contentsOf: repo.appending(path: file.relativePath))
            let patched = try DataFileEditor.apply(fileOps, file: file, to: original)
            let target = directory.appending(path: file.relativePath)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try patched.write(to: target, options: .atomic)
        }
        return DataRoot(repo: repo, overlay: directory)
    }
}
