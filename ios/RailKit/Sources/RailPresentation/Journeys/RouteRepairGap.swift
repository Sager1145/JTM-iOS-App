import RailCore

extension RouteRepair.Gap {
    /// The repair input for one undrawn stretch the route status reported.
    /// A boundary gap names the joining station; a section gap names none.
    public init(_ gap: SectionGap) {
        self.init(
            segmentIndex: gap.segmentIndex, isBoundary: gap.isBoundary,
            station: gap.isBoundary ? gap.from : nil)
    }
}
