import PhotosUI
import RailCore
import SwiftUI
import UIKit
import VisionKit

// =========================================================================
//  TicketScanView.swift — scan a paper ticket from the camera or a photo.
//
//  The picture is read on this device by ``TextRecognizer`` (Vision, no
//  network), the rows go through ``TicketParser``, and the result is shown as a
//  review card: every extracted field with a checkmark. "Apply" hands back the
//  ticked fields only. Not wired into the editor yet — the caller supplies
//  `onApply`.
// =========================================================================

struct TicketScanView: View {
    let region: TicketRegion
    /// Called with the accepted fields only; unticked fields are `nil`.
    let onApply: (TicketReadingResult) -> Void

    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss

    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isReading = false
    @State private var message: String?
    @State private var reading: TicketReadingResult?
    @State private var accepted: Set<TicketScanField> = []
    @State private var readTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if let reading {
                    reviewSection(reading)
                } else {
                    sourceSection
                }
            }
            .navigationTitle(localization.text("ios.ticket.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.text("ios.ticket.cancel")) { dismiss() }
                }
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
            } else {
                Text(localization.text("ios.ticket.cameraUnavailable"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label(localization.text("ios.ticket.photos"), systemImage: "photo.on.rectangle")
            }
            .disabled(isReading)
            if isReading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(localization.text("ios.ticket.reading"))
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(localization.text("ios.ticket.privacy"))
        }
    }

    // MARK: review

    private func reviewSection(_ reading: TicketReadingResult) -> some View {
        Group {
            Section {
                ForEach(TicketScanField.allCases.filter { $0.value(in: reading, localization) != nil }) {
                    field in
                    row(field, reading)
                }
            } header: {
                Text(localization.text("ios.ticket.review"))
            } footer: {
                Text(localization.text("ios.ticket.reviewHint"))
            }
            Section {
                Button {
                    var result = reading
                    for field in TicketScanField.allCases where !accepted.contains(field) {
                        field.clear(&result)
                    }
                    onApply(result)
                    dismiss()
                } label: {
                    Text(localization.text("ios.ticket.apply")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(accepted.isEmpty)
                Button(localization.text("ios.ticket.rescan")) {
                    self.reading = nil
                    accepted = []
                }
            }
        }
    }

    private func row(_ field: TicketScanField, _ reading: TicketReadingResult) -> some View {
        let isOn = accepted.contains(field)
        let confidence = field.confidence(in: reading) ?? 0
        return Button {
            if isOn { accepted.remove(field) } else { accepted.insert(field) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.text(field.titleKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(field.value(in: reading, localization) ?? "")
                        .foregroundStyle(.primary)
                    if confidence < TicketScanField.lowConfidence {
                        Label(localization.text("ios.ticket.lowConfidence"), systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
            reading = result
            accepted = Set(
                TicketScanField.allCases.filter {
                    ($0.confidence(in: result) ?? 0) >= TicketScanField.lowConfidence
                })
        case .success:
            message = localization.text("ios.ticket.nothingFound")
        case .failure(let error):
            message = localization.text(
                (error as? TextRecognizer.TicketFailure) == .unavailable
                    ? "ios.ticket.unavailable" : "ios.ticket.failed")
        }
    }
}

// MARK: - Fields

/// The reviewable fields of a ``TicketReadingResult``. Currency is shown with
/// the fare, so it has no row of its own.
private enum TicketScanField: String, CaseIterable, Identifiable {
    case origin, destination, date, departureTime, serviceName, serviceNumber, car, seat,
        seatClass, fare, kind

    var id: String { rawValue }
    var titleKey: String { "ios.ticket.field.\(rawValue)" }

    /// Below this a field starts unticked and is flagged.
    static let lowConfidence = 0.4

    func confidence(in r: TicketReadingResult) -> Double? {
        switch self {
        case .origin: r.origin?.confidence
        case .destination: r.destination?.confidence
        case .date: r.date?.confidence
        case .departureTime: r.departureTime?.confidence
        case .serviceName: r.serviceName?.confidence
        case .serviceNumber: r.serviceNumber?.confidence
        case .car: r.car?.confidence
        case .seat: r.seat?.confidence
        case .seatClass: r.seatClass?.confidence
        case .fare: r.fare?.confidence
        case .kind: r.kind?.confidence
        }
    }

    /// Clears this field (and the currency, for the fare).
    func clear(_ r: inout TicketReadingResult) {
        switch self {
        case .origin: r.origin = nil
        case .destination: r.destination = nil
        case .date: r.date = nil
        case .departureTime: r.departureTime = nil
        case .serviceName: r.serviceName = nil
        case .serviceNumber: r.serviceNumber = nil
        case .car: r.car = nil
        case .seat: r.seat = nil
        case .seatClass: r.seatClass = nil
        case .fare:
            r.fare = nil
            r.currency = nil
        case .kind: r.kind = nil
        }
    }

    @MainActor func value(in r: TicketReadingResult, _ localization: AppLocalization) -> String? {
        switch self {
        case .origin: return r.origin?.value
        case .destination: return r.destination?.value
        case .date:
            guard let date = r.date?.value else { return nil }
            let md = String(format: "%02d-%02d", date.month, date.day)
            return date.year.map { String(format: "%04d-", $0) + md } ?? md
        case .departureTime:
            guard let time = r.departureTime?.value else { return nil }
            let text = String(format: "%02d:%02d", time.hour, time.minute)
            return time.dayOffset > 0 ? "\(text) +\(time.dayOffset)" : text
        case .serviceName: return r.serviceName?.value
        case .serviceNumber: return r.serviceNumber?.value
        case .car: return r.car?.value
        case .seat: return r.seat?.value
        case .seatClass: return r.seatClass?.value
        case .fare:
            guard let fare = r.fare?.value else { return nil }
            let code = r.currency?.value ?? ""
            let exponent = code == "TWD" ? 2 : 0
            let amount = Decimal(fare) / pow(10, exponent)
            guard !code.isEmpty else { return "\(amount)" }
            return amount.formatted(.currency(code: code).precision(.fractionLength(0...2)))
        case .kind:
            guard let kind = r.kind?.value else { return nil }
            return localization.text("ios.ticket.kind.\(kind.rawValue)")
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
