import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Reads only this task's generated index; reviewers never have to discover
/// screenshots by walking numeric capture directories.
struct DiagnosticCaptureGallery: View {
    let indexPath: String
    let revision: Int
    let controlsEnabled: Bool
    let commands: DiagnosticTaskCommandBridge
    let preview: (URL) -> Void
    @State private var frames: [Frame] = []
    @State private var selected = ""
    @State private var mode = "basemap.png"
    @State private var error: String?

    private struct Frame: Identifiable, Sendable {
        let directory: String
        let label: String
        let files: [String]
        var id: String { directory }
    }
    private var frame: Frame? { frames.first { $0.id == selected } }
    private var selectedIndex: Int? { frames.firstIndex { $0.id == selected } }
    private var modes: [String] { frame?.files.filter { ["basemap.png", "display.png", "smooth.png", "reference.png"].contains($0) } ?? [] }
    private var imageURL: URL? {
        guard let frame, modes.contains(mode) else { return nil }
        return URL(fileURLWithPath: frame.directory).appendingPathComponent(mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Captured views · \(frames.count)").font(.headline)
                Spacer()
                if let imageURL { Button("Preview full image") { preview(imageURL) }.buttonStyle(.bordered) }
            }
            if !frames.isEmpty {
                HStack {
                    Button("Previous view  ⌃⌘J") { moveSelection(by: -1) }
                        .disabled(!controlsEnabled || selectedIndex == nil || selectedIndex == 0)
                    Button("Next view  ⌃⌘K") { moveSelection(by: 1) }
                        .disabled(!controlsEnabled || selectedIndex == nil || selectedIndex == frames.count - 1)
                    Text("Interval and view numbers match capture-index.json (zero-based).")
                        .font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.bordered)
                Picker("Viewpoint", selection: $selected) {
                    ForEach(frames) { Text($0.label).tag($0.id) }
                }.disabled(!controlsEnabled)
                Picker("Image", selection: $mode) {
                    ForEach(modes, id: \.self) { Text($0.replacingOccurrences(of: ".png", with: "").capitalized).tag($0) }
                }.pickerStyle(.segmented)
                if let imageURL {
                    Button { preview(imageURL) } label: { DiagnosticImagePreview(url: imageURL) }
                        .buttonStyle(.plain).accessibilityLabel("Preview captured \(mode) at full resolution")
                    Text(imageURL.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else {
                Text(error ?? "Screenshots appear here as captures finish.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .task(id: indexPath + ":" + String(revision)) { await readIndex() }
        .onChange(of: selected) { _, _ in normalizeMode(); installCommands() }
        .onChange(of: controlsEnabled) { _, _ in installCommands() }
        .onAppear { installCommands() }
        .onDisappear {
            commands.canPreviousCapture = false; commands.canNextCapture = false
            commands.moveCapture = nil
        }
    }

    private func normalizeMode() { if !modes.contains(mode) { mode = modes.first ?? "" } }
    private func moveSelection(by delta: Int) {
        guard controlsEnabled, let current = selectedIndex,
              frames.indices.contains(current + delta) else { return }
        selected = frames[current + delta].id
    }
    private func installCommands() {
        commands.canPreviousCapture = controlsEnabled && selectedIndex.map { $0 > 0 } == true
        commands.canNextCapture = controlsEnabled && selectedIndex.map { $0 < frames.count - 1 } == true
        commands.moveCapture = { moveSelection(by: $0) }
    }
    private func readIndex() async {
        let path = indexPath
        do {
            let loaded = try await Task.detached(priority: .utility) { () throws -> [Frame] in
                guard FileManager.default.fileExists(atPath: path) else { return [] }
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
                return (object?["views"] as? [[String: Any]] ?? []).compactMap { row in
                    guard row["status"] as? String == "captured", let directory = row["directory"] as? String,
                          let id = row["itemID"] as? String, let ordinal = row["pointOrdinal"] as? Int else { return nil }
                    return Frame(directory: directory, label: id + " · view #" + String(ordinal),
                                 files: row["receiptFiles"] as? [String] ?? [])
                }
            }.value
            guard !Task.isCancelled else { return }
            frames = loaded
            if !frames.contains(where: { $0.id == selected }) { selected = frames.first?.id ?? "" }
            normalizeMode(); installCommands(); error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct DiagnosticImagePreview: View {
    let url: URL
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if let error { Label(error, systemImage: "photo.badge.exclamationmark").font(.caption) }
            else { ProgressView("Loading screenshot…") }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 480)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url.path) {
            image = nil; error = nil
            do {
                let path = url.path
                let data = try await Task.detached(priority: .utility) { () throws -> Data in
                    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1200,
                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let buffer = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    CGImageDestinationAddImage(destination, thumbnail, nil)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
                    return buffer as Data
                }.value
                guard !Task.isCancelled else { return }
                image = UIImage(data: data)
                if image == nil { error = "Screenshot could not be decoded." }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
