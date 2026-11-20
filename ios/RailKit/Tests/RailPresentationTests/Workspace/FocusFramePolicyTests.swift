import RailPresentation
import Testing

/// The free map area a focus fit centres in: between the docked menu's inner
/// edge and the map control column's inner edge. Named a regression guard so
/// the merge-time filter runs it.
@Suite("RegressionGuardFocusFramePolicy")
struct RegressionGuardFocusFramePolicy {
    typealias Insets = FocusFramePolicy.Insets
    typealias Span = FocusFramePolicy.Span

    /// The reported Mac window: 1010 pt wide, menu card ending at x = 362,
    /// control buttons starting at x = 960.
    private static let macFallback = Insets(top: 40, left: 398, bottom: 40, right: 40)
    private static let mac = FocusFramePolicy(
        mapWidth: 1010, mapHeight: 700,
        dockedMenu: Span(minX: 16, maxX: 362),
        controlColumn: Span(minX: 960, maxX: 1008),
        fallback: macFallback)

    @Test func reportedMacWindowCentresBetweenMenuAndControls() {
        let free = Self.mac.freeRect
        #expect(free.x == 382)
        #expect(free.maxX == 940)
        #expect(free.midX == 661)
        #expect(free.midX == (362.0 + 960.0) / 2)
        // Nothing under either obstruction.
        #expect(free.x >= 362 + FocusFramePolicy.sideMargin)
        #expect(free.maxX <= 960 - FocusFramePolicy.sideMargin)
        // Vertical rule is the layout's own.
        #expect(free.y == 40)
        #expect(free.height == 620)
        #expect(Self.mac.insets == Insets(top: 40, left: 382, bottom: 40, right: 70))
    }

    /// MapKit fits into the view less its layout margins, and the docked
    /// layout sets the leading margin to the menu's width. The padding handed
    /// to MapKit is what is left after that area, so the menu counts once.
    @Test func mapPaddingIsMeasuredFromTheAreaMapKitFitsInto() {
        let inner = Span(minX: 378, maxX: 1002)
        let padding = Self.mac.mapPadding(fittingArea: inner)
        #expect(padding == Insets(top: 40, left: 4, bottom: 40, right: 62))
        // Where the content lands: inner area less the padding.
        #expect(inner.minX + padding.left == 382)
        #expect(inner.maxX - padding.right == 940)
        #expect((inner.minX + padding.left + inner.maxX - padding.right) / 2 == 661)

        // The cause of the report: view insets handed over as padding put the
        // content between x = 776 and x = 962, under the control buttons.
        #expect(inner.minX + Self.macFallback.left == 776)
        #expect(inner.maxX - Self.macFallback.right == 962)
    }

    @Test func mapPaddingOnAMapThatFitsIntoItsWholeView() {
        let padding = Self.mac.mapPadding(fittingArea: Span(minX: 0, maxX: 1010))
        #expect(padding == Insets(top: 40, left: 382, bottom: 40, right: 70))
    }

    @Test func mapPaddingNeverGoesNegativeAndRejectsAnAreaWithNoRoom() {
        // Inner area already inside the free area on both sides.
        let inside = Self.mac.mapPadding(fittingArea: Span(minX: 400, maxX: 900))
        #expect(inside.left == 0)
        #expect(inside.right == 0)
        // An inner area with no room left gets no side padding at all.
        let none = Self.mac.mapPadding(fittingArea: Span(minX: 0, maxX: 382.5))
        #expect(none == Insets(top: 40, left: 0, bottom: 40, right: 0))
    }

    /// iPhone compact: the menu is a sheet, not docked. Whatever the layout
    /// already asked for comes back untouched, and the control column is not
    /// counted.
    @Test func phoneSheetLayoutIsUnchanged() {
        let today = Insets(top: 40, left: 40, bottom: 360, right: 40)
        let phone = FocusFramePolicy(
            mapWidth: 390, mapHeight: 844,
            dockedMenu: nil,
            controlColumn: Span(minX: 330, maxX: 378),
            fallback: today)
        #expect(!phone.usesFreeArea)
        #expect(phone.insets == today)
        #expect(phone.mapPadding(fittingArea: Span(minX: 16, maxX: 374)) == today)
        #expect(phone.freeRect == FocusFramePolicy.Rect(x: 40, y: 40, width: 310, height: 444))
    }

    /// Hinged layouts carry their sidebar in the fallback's trailing side.
    @Test func hingedLayoutKeepsItsOwnRule() {
        let today = Insets(top: 40, left: 40, bottom: 40, right: 420)
        let hinged = FocusFramePolicy(
            mapWidth: 1200, mapHeight: 800, dockedMenu: nil,
            controlColumn: Span(minX: 700, maxX: 748), fallback: today)
        #expect(hinged.insets == today)
    }

    @Test func dockedMenuWithNoControlColumnKeepsTheBareTrailingInset() {
        let policy = FocusFramePolicy(
            mapWidth: 1010, mapHeight: 700,
            dockedMenu: Span(minX: 16, maxX: 362), controlColumn: nil,
            fallback: Self.macFallback)
        #expect(policy.insets == Insets(top: 40, left: 382, bottom: 40, right: 40))
    }

    @Test func rightToLeftMirrors() {
        // Menu at the right, controls at the left: the same window mirrored.
        let mirrored = FocusFramePolicy(
            mapWidth: 1010, mapHeight: 700,
            dockedMenu: Span(minX: 1010 - 362, maxX: 1010 - 16),
            controlColumn: Span(minX: 1010 - 1008, maxX: 1010 - 960),
            fallback: Self.macFallback)
        #expect(mirrored.insets == Insets(top: 40, left: 70, bottom: 40, right: 382))
        #expect(mirrored.freeRect.midX == 1010 - 661)
        let padding = mirrored.mapPadding(fittingArea: Span(minX: 8, maxX: 632))
        #expect(padding.left == 62)
        #expect(padding.right == 4)
    }

    @Test func narrowWindowDropsTheControlColumnFirst() {
        // 362 + 20 on the left, 50 + 20 on the right leaves 148 of 600: under
        // the 160 minimum, so the controls stop counting.
        let narrow = FocusFramePolicy(
            mapWidth: 600, mapHeight: 500,
            dockedMenu: Span(minX: 16, maxX: 362),
            controlColumn: Span(minX: 550, maxX: 598),
            fallback: Self.macFallback)
        #expect(narrow.insets == Insets(top: 40, left: 382, bottom: 40, right: 40))
        #expect(narrow.freeRect.width == 178)
    }

    @Test func tooNarrowForTheMenuCentresInTheWholeView() {
        let tiny = FocusFramePolicy(
            mapWidth: 520, mapHeight: 500,
            dockedMenu: Span(minX: 16, maxX: 362),
            controlColumn: Span(minX: 470, maxX: 518),
            fallback: Self.macFallback)
        #expect(tiny.insets == Insets(top: 40, left: 40, bottom: 40, right: 40))
        #expect(tiny.freeRect.midX == 260)
    }

    @Test func exactlyTheMinimumWidthStillUsesBothObstructions() {
        // 382 + 70 + 160 = 612.
        let edge = FocusFramePolicy(
            mapWidth: 612, mapHeight: 500,
            dockedMenu: Span(minX: 16, maxX: 362),
            controlColumn: Span(minX: 562, maxX: 610),
            fallback: Self.macFallback)
        #expect(edge.insets.left == 382)
        #expect(edge.insets.right == 70)
    }

    @Test func bottomObstructionPassesThrough() {
        var fallback = Self.macFallback
        fallback.bottom = 300
        var policy = Self.mac
        policy.fallback = fallback
        #expect(policy.insets.bottom == 300)
        #expect(policy.mapPadding(fittingArea: Span(minX: 378, maxX: 1002)).bottom == 300)
        #expect(policy.freeRect.height == 360)
    }

    @Test func unlaidOutMapUsesTheFallback() {
        let policy = FocusFramePolicy(
            mapWidth: 0, mapHeight: 0, dockedMenu: Span(minX: 0, maxX: 362),
            controlColumn: nil, fallback: Self.macFallback)
        #expect(policy.insets == Self.macFallback)
        #expect(policy.freeRect.width == 0)
    }
}
