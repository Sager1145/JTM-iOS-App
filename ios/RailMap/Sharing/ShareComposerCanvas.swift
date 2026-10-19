import SwiftUI
import UIKit

struct ShareComposerCanvas: View {
    @Environment(AppLocalization.self) private var localization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var model: ShareComposerModel
    @Binding var isEditing: Bool
    @Binding var interaction: ShareComposerInteraction?
    let images: [UUID: UIImage]
    let statisticsReady: Bool
    let accessibilityLabels: [UUID: String]
    let onSizeChange: (CGSize) -> Void
    let onCardGesture: (ShareCard, CGRect, ShareCardGestureEvent) -> Void

    var body: some View {
        let pixels = model.size.pixelSize(for: model.ratio)
        GeometryReader { proxy in
            canvasContent(size: proxy.size)
                .background {
                    Color.clear.preference(
                        key: ShareComposerFramePreferenceKey.self,
                        value: ["canvas": proxy.frame(in: .global)])
                }
        }
        .aspectRatio(pixels.width / pixels.height, contentMode: .fit)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .animation(layoutAnimation, value: model.ratio)
        .accessibilityLabel(localization.text("ios.stats.shareCanvas"))
        .accessibilityElement(children: .contain)
    }

    private func canvasContent(size: CGSize) -> some View {
        let cards = displayedCards
        let frames = ShareCanvasGeometry.frames(cards: cards, grid: model.grid, canvasSize: size)

        return ZStack {
            Color.railElevated(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isEditing, interaction == nil else { return }
                    withAnimation(layoutAnimation) { isEditing = false }
                }

            ForEach(cards) { card in
                if let frame = frames[card.id] {
                    cardView(card, frame: frame)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .onAppear { onSizeChange(size) }
        .onChange(of: size) { _, newValue in onSizeChange(newValue) }
    }

    private var displayedCards: [ShareCard] {
        guard let interaction, interaction.previewingCanvas, interaction.isLifted else {
            return model.cards
        }
        let byID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        return interaction.tentativeOrder.compactMap { id in
            guard var card = byID[id] else { return nil }
            if id == interaction.id { card.parked = false }
            return card
        }
    }

    @ViewBuilder
    private func cardView(_ card: ShareCard, frame: CGRect) -> some View {
        let isLifted = interaction?.id == card.id && interaction?.isLifted == true
        let index = model.cards.firstIndex(where: { $0.id == card.id }) ?? 0
        ZStack(alignment: .topLeading) {
            ShareCardGestureLayer(isEditing: isEditing) {
                ShareComposerCardImage(
                    card: card,
                    image: images[card.id],
                    statisticsReady: statisticsReady,
                    reduceMotion: reduceMotion
                )
                .frame(width: frame.width, height: frame.height)
                .background(Color.railElevated(.systemBackground))
                .clipShape(RoundedRectangle(
                    cornerRadius: cornerRadius(card, frame: frame), style: .continuous))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius(card, frame: frame),
                        style: .continuous)
                    .stroke(model.selectedCardID == card.id ? Color.accentColor : .clear,
                            lineWidth: 3)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabels[card.id] ?? "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(model.selectedCardID == card.id ? .isSelected : [])
                .accessibilityIdentifier("shareComposerCard-\(index)")
                .accessibilityAction { model.selectedCardID = card.id }
                .accessibilityAction(named: Text(localization.text(
                    "ios.stats.shareMotion.moveEarlier"))) {
                    guard interaction == nil else { return }
                    withAnimation(layoutAnimation) { model.moveEarlier(card.id) }
                }
                .accessibilityAction(named: Text(localization.text(
                    "ios.stats.shareMotion.moveLater"))) {
                    guard interaction == nil else { return }
                    withAnimation(layoutAnimation) { model.moveLater(card.id) }
                }
                .accessibilityAction(named: Text(localization.text(
                    "ios.stats.shareMotion.remove"))) {
                    guard interaction == nil else { return }
                    withAnimation(layoutAnimation) { model.remove(card.id) }
                }
            } onEvent: { event in
                onCardGesture(card, frame, event)
            }

            if isEditing {
                removeBadge(card, index: index)
                    .disabled(interaction != nil)
                    .offset(x: -17, y: -17)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .modifier(ShareComposerWobble(
            active: isEditing && !isLifted && !reduceMotion,
            seed: card.id.hashValue))
        .position(x: frame.midX, y: frame.midY)
        .opacity(isLifted ? 0 : 1)
        .accessibilityHidden(isLifted)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .zIndex(isLifted ? 100 : 0)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
        .animation(isLifted ? nil : layoutAnimation, value: frame)
    }

    private func removeBadge(_ card: ShareCard, index: Int) -> some View {
        Button {
            withAnimation(layoutAnimation) { model.remove(card.id) }
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.red, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(radius: 2, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localization.text("ios.stats.shareMotion.remove"))
        .accessibilityIdentifier("shareComposerRemove-\(index)")
    }

    private var layoutAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.78)
    }

    private func cornerRadius(_ card: ShareCard, frame: CGRect) -> CGFloat {
        ShareCanvasGeometry.cornerRadius(card: card, frame: frame)
    }
}

struct ShareComposerLiftedCard: View {
    let card: ShareCard
    let image: UIImage?
    let statisticsReady: Bool
    let reduceMotion: Bool
    let size: CGSize
    let isRaised: Bool
    var trayTitle: String? = nil
    var trayCaption: String? = nil
    @State private var hasAppeared = false

    var body: some View {
        face
        .frame(width: size.width, height: size.height)
        .background(Color.railElevated(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .scaleEffect(reduceMotion || !isRaised || !hasAppeared ? 1 : 1.06)
        .shadow(color: .black.opacity(isRaised && hasAppeared ? 0.28 : 0.08),
                radius: isRaised && hasAppeared ? 16 : 4, y: isRaised && hasAppeared ? 8 : 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder
    private var face: some View {
        if let trayTitle, let trayCaption {
            VStack(alignment: .leading, spacing: 6) {
                Label(trayTitle, systemImage: "rectangle.slash")
                Text(trayCaption).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
        } else {
            ShareComposerCardImage(
                card: card, image: image,
                statisticsReady: statisticsReady, reduceMotion: reduceMotion)
        }
    }

    private var cornerRadius: CGFloat {
        if trayTitle != nil { return 10 }
        return ShareCanvasGeometry.cornerRadius(card: card, frame: CGRect(origin: .zero, size: size))
    }
}

struct ShareComposerCardImage: View {
    let card: ShareCard
    let image: UIImage?
    let statisticsReady: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if statisticsReady, let visibleImage = image {
                Image(uiImage: visibleImage)
                    .resizable()
                    .scaledToFit()
                    .id(ObjectIdentifier(visibleImage))
                    .transition(.opacity)
            } else {
                ShareComposerPlaceholder(card: card, animated: !reduceMotion)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: image.map(ObjectIdentifier.init))
    }

}

private struct ShareComposerPlaceholder: View {
    let card: ShareCard
    let animated: Bool
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                placeholderColor
                if animated {
                    LinearGradient(colors: [.clear, .white.opacity(0.18), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: proxy.size.width * 0.45)
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * proxy.size.width * 1.5)
                }
            }
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var placeholderColor: Color {
        switch card.kind {
        case .ticket: Color.accentColor.opacity(0.16)
        case .map: Color.green.opacity(0.16)
        case .stat: Color.blue.opacity(0.14)
        }
    }
}

struct ShareComposerWobble: ViewModifier {
    let active: Bool
    let seed: Int

    /// One structure whether or not the card wobbles. Swapping a
    /// `TimelineView` in and out would recreate the card's gesture view, and a
    /// card lifted mid-press would lose the finger that lifted it; a paused
    /// timeline costs no frames and keeps the gesture's identity.
    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = Double(abs(seed % 97)) / 97 * 2 * Double.pi
            content.rotationEffect(
                .degrees(active ? sin(time * 2 * .pi / 0.26 + phase) * 1.3 : 0))
        }
    }
}
