import Foundation
import RailCore

/// The N02 edge indexes the 已乘路線顯示 filter classifies against, one per
/// region that has rides — and the build that fills them in.
///
/// ## Why these two belong to one type
///
/// They were two `@State`s on `RailWorkspaceView` and a ten-line `for` loop
/// inside a `.task`, which is the shape this codebase's own guidance warns
/// about: a cancellation check, a `defer` and an `await` per region, sitting
/// in a view body's blast radius. The dictionary and the flag are also not
/// two facts — the flag means "the dictionary is still filling in", and
/// nothing but the build may set either.
///
/// The workspace keeps what this cannot know: WHEN to ask. That is
/// `categoryIndexKey`, and it is made of the filter's state and the regions
/// that have rides, neither of which is this type's business.
///
/// ## What the emptiness is worth
///
/// Empty until the reader actually switches a category off. Building one
/// parses a whole region's rail network, and three of the four boxes being
/// ticked is the state the map spends its life in — so the default path pays
/// nothing, exactly as `riddenFeatureCategory` is only reached in the web app
/// when `anyRiddenCategoryHidden()`.
///
/// Never torn down, either: a reader who ticks 地下鐵 back off a minute later
/// should not wait for the network to be read a second time.
@MainActor
@Observable
final class CategoryIndexes {

    /// What has been built so far, by country. Published as each region's
    /// index lands rather than when the last one does.
    private(set) var byCountry: [String: Statistics.EdgeIndex] = [:]

    /// Whether an index is being built right now.
    ///
    /// Reading a region's network takes seconds, and until it lands every ride
    /// stays visible — so without this the first tick of a category box is a
    /// control that appears to do nothing, which is indistinguishable from one
    /// that is broken.
    private(set) var isBuilding = false

    /// Build whatever these countries still lack, off the main actor.
    ///
    /// Countries already held are skipped, so a caller may pass the whole list
    /// on every change without re-reading anything.
    func load(for countries: [String]) async {
        let wanted = countries.filter { byCountry[$0] == nil }
        guard !wanted.isEmpty else { return }
        isBuilding = true
        defer { isBuilding = false }
        for country in wanted {
            guard let index = try? await EdgeIndexCache.shared.index(country: country)
            else { continue }
            // Checked AFTER the await and before the publish: a cancelled task
            // whose index already arrived must not write it, or the next build
            // would skip a country whose entry was never actually drawn from.
            if Task.isCancelled { return }
            byCountry[country] = index
        }
    }
}
