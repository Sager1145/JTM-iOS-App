import Foundation

/// Slices one railway line's chunk out of a region's display blob.
///
/// `rail-display-network v2` ships one concatenated blob per region
/// (`{region}.display.bin`) rather than one file per line. The app
/// memory-maps that blob (`Data(contentsOf:options:.alwaysMapped)`) and each
/// manifest line header carries the `{offset,length,sha256}` of its chunk
/// inside it — a chunk being the whole JSON document for one railway line,
/// never a fragment of one, because geometry is never tiled. This type does
/// the one arithmetic step of turning `(offset, length)` into the bytes of
/// that document, kept overflow-safe and rebased so it also works when the
/// `Data` handed in is itself already a slice of something larger.
public enum DisplayChunkError: Error, Equatable {
    case outOfRange(offset: Int, length: Int, blobBytes: Int)
}

public enum DisplayChunkReader {

    /// Returns a zero-based copy of `blob[offset, offset+length)`.
    ///
    /// Bounds are checked without overflowing (`blob.count - offset >= length`
    /// is computed as `offset <= blob.count - length` once `length` is known
    /// to be positive and `offset` non-negative), and the resulting range is
    /// rebased onto `blob.startIndex` because a `Data` value that is itself a
    /// slice of a larger buffer does not start its indices at zero.
    public static func slice(_ blob: Data, offset: Int, length: Int) throws -> Data {
        guard offset >= 0, length > 0, offset <= blob.count - length else {
            throw DisplayChunkError.outOfRange(offset: offset, length: length, blobBytes: blob.count)
        }
        let start = blob.startIndex + offset
        let end = start + length
        return blob.subdata(in: start..<end)
    }
}
