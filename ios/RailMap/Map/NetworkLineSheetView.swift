import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// The sheet a tap on a network line opens: the existing ``RailwayLineCardView``
/// in a sheet of its own, with the focus behaviour the station card gives it —
/// once the card is shown, it sits at the compact height and the map frames the
/// line above it.
struct NetworkLineSheetView: View {
    var target: NetworkLineTarget
    var network: RailNetworkStore
    var controller: RailMapController
    var onPreview: (RailwayLinePreview?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.popupHost) private var popupHost
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePanelSurface) private var closePanelSurface
    @State private var detent: PresentationDetent = .medium
    @State private var lineIsShown = false
    @State private var sheetHeight: CGFloat = 0
    @State private var sheetContentHeight: CGFloat = 0
    @State private var pendingFocus: MKMapRect?

    var body: some View {
        NavigationStack {
            RailwayLineCardView(
                row: target.row, region: target.region, network: network,
                onPreview: { preview in
                    lineIsShown = preview != nil
                    onPreview(preview)
                    if preview == nil {
                        detent = .medium
                        pendingFocus = nil
                        controller.journeyMenuBottomObstruction = nil
                    }
                },
                onLocate: requestFocus,
                onClose: { if let closePanelSurface { closePanelSurface() } else { dismiss() } })
        }
        #if !targetEnvironment(macCatalyst)
        .presentationDetents( // ui-token-ok: hand-built detents, as the station card's
            lineIsShown && !dynamicTypeSize.isAccessibilitySize
                ? [.height(WorkspaceMenuMetrics.journeyCompactHeight), .medium, .large]
                : [.medium, .large], selection: $detent)
        #endif
        .onGeometryChange(for: SheetMeasurements.self) { proxy in
            SheetMeasurements(height: proxy.size.height, bottomInset: proxy.safeAreaInsets.bottom)
        } action: { measurements in
            sheetContentHeight = measurements.height
            sheetHeight = measurements.height + measurements.bottomInset
            #if targetEnvironment(macCatalyst)
            if lineIsShown { controller.journeyMenuBottomObstruction = 0 }
            #else
            if lineIsShown { controller.journeyMenuBottomObstruction = popupHost == .panel ? 0 : sheetHeight }
            #endif
            focusIfReady()
        }
        .onDisappear { controller.journeyMenuBottomObstruction = nil }
        .railMenuPresentationBackground()
        .railMenuPresentationCornerRadius()
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
    }

    private struct SheetMeasurements: Equatable {
        var height: CGFloat
        var bottomInset: CGFloat
    }

    private func requestFocus(_ rect: MKMapRect) {
        pendingFocus = rect
        #if !targetEnvironment(macCatalyst)
        if popupHost != .panel {
        withAnimation(RailMotion.spring) {
            detent = dynamicTypeSize.isAccessibilitySize ? .large
                : .height(WorkspaceMenuMetrics.journeyCompactHeight)
        }
        }
        #endif
        focusIfReady()
    }

    private func focusIfReady() {
        guard let rect = pendingFocus, sheetHeight > 0 else { return }
        #if !targetEnvironment(macCatalyst)
        guard popupHost == .panel || dynamicTypeSize.isAccessibilitySize
            || sheetContentHeight <= WorkspaceMenuMetrics.journeyCompactHeight + 1 else { return }
        #endif
        pendingFocus = nil
        #if targetEnvironment(macCatalyst)
        controller.journeyMenuBottomObstruction = 0
        #else
        controller.journeyMenuBottomObstruction = popupHost == .panel ? 0 : sheetHeight
        #endif
        controller.fit(rect)
    }
}

/// Several network lines under one finger, as a list. Picking one is the answer;
/// the caller closes this sheet and opens that line's card.
struct NetworkLineChooserView: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closePanelSurface) private var closePanelSurface

    var targets: [NetworkLineTarget]
    var onPick: (NetworkLineTarget) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PopupMenuHeader(
                    title: localization.countryText("popup.line", fallback: "Line")
                ) {
                    PanelBackButton()
                    SheetCloseButton(
                        accessibilityLabel: Text(localization.text("ios.close", fallback: "Close")),
                        action: { if let closePanelSurface { closePanelSurface() } else { dismiss() } })
                        .accessibilityIdentifier("lineChooserClose")
                }
                List {
                    ForEach(targets) { target in
                        Button {
                            onPick(target)
                        } label: {
                            StationCardLineRow(row: target.row)
                        }
                        .buttonStyle(RailRowPressStyle())
                        .accessibilityIdentifier("lineChooser.\(target.row.lineID)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Color.railMenuBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .railSheet(.half)
        .railMenuPresentationBackground()
        .railMenuPresentationCornerRadius()
        .presentationContentInteraction(.resizes)
    }
}
