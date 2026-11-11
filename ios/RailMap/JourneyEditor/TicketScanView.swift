import PhotosUI
import RailCore
import SwiftUI
import UIKit
import VisionKit

// =========================================================================
//  TicketScanView.swift — scan a paper ticket from the camera or a photo.
//
//  The picture is read on this device by ``TextRecognizer`` (Vision, no
//  network) and the rows go through ``TicketParser``. One shot: a reading with
//  anything in it is handed to `onApply` whole and the sheet closes; the
//  editor fills every field the reader has not set and tags each with its
//  source, so the review happens on the form itself.
// =========================================================================

struct TicketScanView: View {
    let region: TicketRegion
    /// Called once with everything the ticket gave.
    let onApply: (TicketReadingResult) -> Void

    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isReading = false
    @State private var message: String?
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
            }
            .accessibilityIdentifier("ticketScanForm")
            .navigationTitle(localization.text("ios.ticket.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                RailEditingToolbar(cancelTitle: Text(localization.text("ios.cancel", fallback: "Cancel")), onCancel: { dismiss() })
            }
            .fullScreenCover(isPresented: $showsCamera) {
                DocumentCameraPicker(
                    onScan: { images in
                        showsCamera = false
                        read(images)
                    },
                    onCancel: { showsCamera = false })
                .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                loadPhoto(item)
            }
            .onDisappear { readTask?.cancel() }
        }
    }

    // MARK: source

    private var sourceSection: some View {
        Section {
            if DocumentCameraPicker.isSupported {
                Button {
                    message = nil
                    showsCamera = true
                } label: {
                    Label(localization.text("ios.ticket.camera"), systemImage: "camera")
                }
                .disabled(isReading)
                .accessibilityIdentifier("ticketScanCamera")
            } else {
                Text(localization.text("ios.ticket.cameraUnavailable"))
                    .railText(.secondary)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label(localization.text("ios.ticket.photos"), systemImage: "photo.on.rectangle")
            }
            .disabled(isReading)
            .accessibilityIdentifier("ticketScanPhotos")
            if isReading {
                HStack(spacing: RailSpacing.s8) {
                    ProgressView()
                    Text(localization.text("ios.ticket.reading"))
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                RailStatusLabel(kind: .error, text: message)
            }
        } footer: {
            Text(localization.text("ios.ticket.privacy"))
        }
    }

    // MARK: reading

    private func loadPhoto(_ item: PhotosPickerItem) {
        message = nil
        isReading = true
        readTask?.cancel()
        readTask = Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                isReading = false
                message = localization.text("ios.ticket.failed")
                return
            }
            await run([image])
        }
    }

    private func read(_ images: [UIImage]) {
        message = nil
        isReading = true
        readTask?.cancel()
        readTask = Task { await run(images) }
    }

    private func run(_ images: [UIImage]) async {
        let region = region
        let outcome: Result<TicketReadingResult, Error> = await Task.detached(priority: .userInitiated) {
            do {
                var lines: [RecognizedLine] = []
                for image in images {
                    try Task.checkCancellation()
                    guard let cgImage = image.uprightCGImage() else { continue }
                    lines += try TextRecognizer.recognizeTicket(cgImage, region: region)
                }
                return .success(TicketParser.parse(lines: lines, region: region))
            } catch {
                return .failure(error)
            }
        }.value
        guard !Task.isCancelled else { return }
        isReading = false
        switch outcome {
        case .success(let result) where !result.isEmpty:
            onApply(result)
            dismiss()
        case .success:
            message = localization.text("ios.ticket.nothingFound")
        case .failure(let error):
            message = localization.text(
                (error as? TextRecognizer.TicketFailure) == .unavailable
                    ? "ios.ticket.unavailable" : "ios.ticket.failed")
        }
    }
}

// MARK: - UIKit

private extension UIImage {
    /// The bitmap with its orientation applied, so Vision reads it upright.
    func uprightCGImage() -> CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

/// `VNDocumentCameraViewController`: live edge detection and perspective
/// correction, so the recogniser sees a flat ticket.
private struct DocumentCameraPicker: UIViewControllerRepresentable {
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}
