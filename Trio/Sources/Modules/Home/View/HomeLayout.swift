import CoreGraphics

/// Fixed zone heights for the non-scrolling Home dashboard. The bobble is a fixed
/// 130pt circle, so the header is constant; the chart gets the remainder. Tai has
/// no permanent nav bar on Home — warnings surface through the multi-use panel
/// in the bottom zone.
enum HomeLayout {
    /// Zone B: air above the header; sized so an up-pointing trend arrow clears
    /// the status bar.
    static let headerTopPadding: CGFloat = 12
    /// Zone B: left info panel / glucose bobble / loop status header.
    static let headerHeight: CGFloat = 150
    /// Zone C: horizontal pump panel slot; the row centers inside it.
    static let mealSlotHeight: CGFloat = 30
    /// Pull distance that triggers the forced loop.
    static let refreshTriggerDistance: CGFloat = 70
    /// Height of the pull-down hint row shown in the rubber-band gap.
    static let refreshIndicatorHeight: CGFloat = 40
    /// Zone E: rounded panel shared by the adjustment and bolus views.
    /// Name + one caption line with breathing room to the border.
    static let bottomPanelHeight: CGFloat = 50
    /// Zone E: horizontal inset of the panel.
    static let bottomPanelHorizontalPadding: CGFloat = 10
    /// Zone E: air above the panel.
    static let bottomZoneTopPadding: CGFloat = 8
    /// Zone E: air between panel and tab bar.
    static let bottomZoneBottomPadding: CGFloat = 8
    /// Zone E: total height including padding.
    static var bottomZoneHeight: CGFloat {
        bottomPanelHeight + bottomZoneTopPadding + bottomZoneBottomPadding
    }

    /// Zone D: breathing room above and below the chart's pane stack.
    static let chartVerticalPadding: CGFloat = 8
    /// last-resort chart floor; must stay below the tightest natural allocation
    /// (SE under the iOS 26 tab bar + accessory leaves ~140) or the bottom zone overflows
    static let chartMinHeight: CGFloat = 130
}
