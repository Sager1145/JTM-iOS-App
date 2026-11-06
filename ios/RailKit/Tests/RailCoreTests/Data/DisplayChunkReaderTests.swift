import Foundation
import Testing

@testable import RailCore

/// `DisplayChunkReader.slice` is the one arithmetic step between a
/// memory-mapped region blob and one railway line's JSON document, so it is
/// exercised directly against an in-memory blob rather than a shared fixture
/// — there is no Python-side counterpart to this reader to stay parity with.
struct DisplayChunkReaderTests {

    private struct Doc: Codable, Equatable {
        let lineId: String
        let value: Int
    }

    /// Three documents concatenated into one blob, each recovered by its
    /// recorded `(offset, length)` and JSON-decoded back to the original.
    @Test
    func slicesAndDecodesEachDocument() throws {
        let docs = [
            Doc(lineId: "a", value: 1),
            Doc(lineId: "b", value: 2),
            Doc(lineId: "c", value: 3),
        ]
        var blob = Data()
        var ranges: [(offset: Int, length: Int)] = []
        for doc in docs {
            let encoded = try JSONEncoder().encode(doc)
            ranges.append((offset: blob.count, length: encoded.count))
            blob.append(encoded)
        }

        for (doc, range) in zip(docs, ranges) {
            let sliced = try DisplayChunkReader.slice(blob, offset: range.offset, length: range.length)
            let decoded = try JSONDecoder().decode(Doc.self, from: sliced)
            #expect(decoded == doc)
        }
    }

    /// Slicing a `Data` that is itself already a slice of a larger buffer
    /// must rebase on `blob.startIndex` rather than assume indices start at
    /// zero, and return the same bytes as slicing the equivalent standalone
    /// blob would.
    @Test
    func rebasesWhenTheInputIsAlreadyASlice() throws {
        let padding = Data(repeating: 0xFF, count: 7)
        let payload = Data("hello world".utf8)
        var whole = padding
        whole.append(payload)

        let subslice = whole[padding.count...]
        #expect(subslice.startIndex != 0)

        let sliced = try DisplayChunkReader.slice(subslice, offset: 0, length: payload.count)
        #expect(sliced == payload)
    }

    /// `offset + length == count` is exactly the last valid chunk.
    @Test
    func offsetPlusLengthEqualToCountSucceeds() throws {
        let blob = Data("0123456789".utf8)
        let sliced = try DisplayChunkReader.slice(blob, offset: 6, length: 4)
        #expect(sliced == Data("6789".utf8))
    }

    /// `offset + length == count + 1` runs one byte past the end.
    @Test
    func offsetPlusLengthOneOverCountThrows() {
        let blob = Data("0123456789".utf8)
        #expect(throws: DisplayChunkError.self) {
            try DisplayChunkReader.slice(blob, offset: 7, length: 4)
        }
    }

    /// A zero-length chunk is not a valid document.
    @Test
    func zeroLengthThrows() {
        let blob = Data("0123456789".utf8)
        #expect(throws: DisplayChunkError.self) {
            try DisplayChunkReader.slice(blob, offset: 0, length: 0)
        }
    }

    /// A negative offset is never valid.
    @Test
    func negativeOffsetThrows() {
        let blob = Data("0123456789".utf8)
        #expect(throws: DisplayChunkError.self) {
            try DisplayChunkReader.slice(blob, offset: -1, length: 4)
        }
    }

    /// `offset = Int.max` must be rejected by comparison, not by an overflow
    /// trap while computing bounds.
    @Test
    func offsetAtIntMaxThrowsWithoutTrapping() {
        let blob = Data("0123456789".utf8)
        #expect(throws: DisplayChunkError.self) {
            try DisplayChunkReader.slice(blob, offset: Int.max, length: 4)
        }
    }
}
