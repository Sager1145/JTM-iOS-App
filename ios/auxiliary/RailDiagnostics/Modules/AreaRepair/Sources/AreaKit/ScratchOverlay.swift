import Foundation

/// A scratch copy of only the files a patch stack touches, with every op
/// applied (report-only ops included, so a preview shows their effect).
/// Junction rows are checked against the registry rules (JunctionRowRules)
/// before anything is written.
/// The overlay is a pure function of (repository, patch stack): undoing a
/// patch is popping it and materialising again.
public enum ScratchOverlay {
    /// Rebuilds `directory` from the repository and `patches` and returns a
    /// root that reads patched files from it. Only AreaKit-owned paths under
    /// `directory` (the repository-relative data paths) are replaced.
    @discardableResult
    public static func materialize(repo: URL, patches: [AreaPatch], into directory: URL) throws -> DataRoot {
        try refuseRepositoryDirectory(directory, repo: repo)
        let fm = FileManager.default
        for file in DataFile.allCases {
            let target = directory.appending(path: file.relativePath)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        }
        let ops = patches.flatMap(\.ops)
        try JunctionRowRules.validateLineIDs(ops, packageURL: repo.appending(path: DataFile.package.relativePath))
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

    /// Refuses a scratch directory that would delete or overwrite repository
    /// data: the repository itself or an ancestor of it, anything inside its
    /// app/ tree, or one whose data-file targets resolve (through symlinks)
    /// to existing repository data files.
    static func refuseRepositoryDirectory(_ directory: URL, repo: URL) throws {
        let scratch = resolved(directory), root = resolved(repo)
        func refuse(_ why: String) -> AreaRepairError {
            .refused("scratch directory \(directory.path) \(why); choose a directory outside the repository's data.")
        }
        if root.starts(with: scratch) {
            throw refuse(scratch == root ? "is the repository root" : "contains the repository")
        }
        if scratch.starts(with: root + ["app"]) { throw refuse("is inside the repository's app/ tree") }
        let repoFiles = Set(DataFile.allCases.map { resolved(repo.appending(path: $0.relativePath)) })
        for file in DataFile.allCases where repoFiles.contains(resolved(directory.appending(path: file.relativePath))) {
            throw refuse("would replace the repository's \(file.relativePath)")
        }
    }

    /// Path components with symlinks resolved: the longest existing ancestor
    /// through realpath(3), the rest appended after standardising.
    static func resolved(_ url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                return URL(fileURLWithPath: String(cString: real)).pathComponents + rest.reversed()
            }
            rest.append(existing.lastPathComponent)
            existing = existing.deletingLastPathComponent()
        }
        return ["/"] + rest.reversed()
    }
}
