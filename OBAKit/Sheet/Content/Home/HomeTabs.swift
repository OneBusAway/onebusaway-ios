//
//  HomeTabs.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import Synchronization
import OBAKitCore

/// A tab of the home sheet on iPhone, drawn as a filter chip under the search
/// field: the tabs sit where the rider's thumb already is after a search, and
/// leave the bottom of the sheet to its content.
///
/// For You is the mixed view: bookmarks, what leaves nearby, recent stops and
/// shortcuts. Each of the others is one of its sections at full length, so a
/// section's header and its chip lead to the same place. More, a tab of the
/// classic app, is a shortcut in For You's Explore row.
enum HomeTab: CaseIterable, Hashable {
    case home
    case bookmarks
    case nearby
    case recent

    var title: String {
        switch self {
        case .home:
            OBALoc("home_sheet.tab.for_you", value: "For You", comment: "Title of the first filter on the map panel's home sheet: the mixed view of the rider's bookmarks, departures from nearby stops, and recent stops. Short: it is a chip in a row of four.")
        case .bookmarks: Strings.bookmarksTabTitle
        case .nearby:
            OBALoc("home_sheet.tab.nearby", value: "Nearby", comment: "Title of a filter on the map panel's home sheet that lists the stops near the center of the map. Short: it is a chip in a row of four.")
        case .recent: Strings.recentTabTitle
        }
    }

    /// The tab a home section's header goes to, or `nil` for a route that is no
    /// section's index.
    init?(seeAll route: AppSheetRoute) {
        switch route {
        case .recentStopsAll: self = .recent
        case .bookmarksAll: self = .bookmarks
        case .nearbyAll: self = .nearby
        default: return nil
        }
    }
}

/// The rules for the home sheet's tabs, kept apart from the views so they can be
/// tested without one.
enum HomeTabs {

    /// iPhone only for now: a regular-width sheet keeps the single home page.
    /// `nil`, before the first layout pass reports a size class, counts as compact.
    static func showsTabs(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass != .regular
    }

    /// Less room than a row under the chips and no tab shows its page there.
    /// `nonisolated`, like `showsTabPages`, for `onGeometryChange`'s transform,
    /// which runs off the main actor.
    nonisolated static let minimumListRoom: CGFloat = 44

    /// Whether the tabs' pages show under the chips, given the height of the
    /// pages' area.
    ///
    /// Collapsed, the sheet is the search field over the chips, whichever tab is
    /// picked: the detent fits those two rows and no more, and every tab hides
    /// its page. Whatever sliver the system leaves, a page peeking through it
    /// reads as cut off. Measured rather than read off the detent, so the pages
    /// follow a drag rather than appearing when it settles.
    nonisolated static func showsTabPages(showsTabs: Bool, pageHeight: CGFloat) -> Bool {
        !showsTabs || pageHeight >= minimumListRoom
    }

    /// How far the map has to move before the Nearby tab's list is rebuilt
    /// around its new center: about a block, less than which the same stops
    /// are near.
    static let nearbyAnchorTolerance: CLLocationDistance = 150

    /// Where the Nearby tab's list should be centered when the tab is picked:
    /// where it already is, unless the map has moved away from there.
    static func nearbyAnchor(current: CLLocationCoordinate2D?, mapCenter: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        guard let current, let mapCenter else { return mapCenter ?? current }
        let moved = CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude))
        return moved > nearbyAnchorTolerance ? mapCenter : current
    }

    /// Whether a page's 30-second poll runs: only while the rider can see the page.
    /// Not when a stacked sheet covers it, and not when the home sheet is collapsed
    /// and the page is hidden (see `showsTabPages`).
    static func shouldPoll(isOnScreen: Bool, isCovered: Bool, isCollapsed: Bool) -> Bool {
        isOnScreen && !isCovered && !isCollapsed
    }

    /// Under the search field. With the 4 pt `HomeTabBar` pads its row by, and
    /// the 4 pt a chip's capsule is drawn inside that row, the field and the
    /// chips read as 12 pt apart.
    nonisolated static let searchRowBottomPadding: CGFloat = 4

    /// Above the search field, on any sheet taller than collapsed.
    nonisolated static let searchRowStandardTopPadding: CGFloat = 16

    /// Under the chips, before the page's own top margin.
    static let chipsBottomPadding: CGFloat = 4

    /// The header the collapsed detent is fitted to, for a search field
    /// `fieldHeight` tall: the field with its standard padding.
    nonisolated static func headerHeight(fieldHeight: CGFloat) -> CGFloat {
        searchRowStandardTopPadding + fieldHeight + searchRowBottomPadding
    }

    /// Above the search field, for a sheet `sheetHeight` tall.
    ///
    /// Collapsed, the sheet is the search field alone, centered in it: the
    /// sheet is drawn no shorter than `AppSheetRoute.homeCollapsedHeight`, which
    /// is more than the field and its standard padding, and a field pinned to
    /// the top would leave a band of nothing under it. As the sheet rises the
    /// padding falls back to the standard, point for point, so the field
    /// follows the drag rather than jumping when it settles, and the chips
    /// come up under it.
    ///
    /// The collapsed sheet lays its content out at the height it's drawn
    /// (`HomeCollapsedDetent.collapsedHeight`), not the shorter one its detent
    /// asks for, so that's the height it rises from.
    nonisolated static func searchRowTopPadding(fieldHeight: CGFloat, sheetHeight: CGFloat) -> CGFloat {
        let collapsedHeight = HomeCollapsedDetent.collapsedHeight(headerHeight: headerHeight(fieldHeight: fieldHeight))
        let centered = (collapsedHeight - fieldHeight) / 2
        let rise = max(0, sheetHeight - collapsedHeight)
        return max(searchRowStandardTopPadding, centered - rise)
    }

    /// Whether the chips have room to show under the search field: all of
    /// their row. Less, and they're clipped, which is fine mid-drag, but
    /// neither tappable nor read by VoiceOver.
    nonisolated static func showsChips(room: CGFloat, chipsHeight: CGFloat) -> Bool {
        chipsHeight > 0 && room >= chipsHeight - 1
    }

    /// Where the sheet goes when a tab is picked, or `nil` to leave it.
    ///
    /// Collapsed, the sheet shows only the search field and the chips, so a
    /// picked tab would change nothing the rider can see. It rises to `.medium`.
    static func detent(afterSelectingFrom currentDetent: PresentationDetent) -> PresentationDetent? {
        currentDetent == AppSheetRoute.homeCollapsedDetent ? .medium : nil
    }

    /// Room a tab's page leaves at its bottom for the home indicator.
    ///
    /// Sheet content ignores the safe area, so it can't read this itself. A
    /// floating sheet, collapsed or at `.medium` on iOS 26, stops short of the
    /// screen's edge, and the home indicator may cross it, as in Find My; a sheet
    /// reaching the edge needs the whole inset.
    static func bottomClearance(sheetBottom: CGFloat, screen: ScreenBottom) -> CGFloat {
        guard let edge = screen.edge, sheetBottom >= edge - 1 else { return 0 }
        return screen.inset
    }
}

/// The home sheet's smallest detent: the search row, and no more.
///
/// Fitted to that header as laid out, measured by `HomeSheetView`, so it holds
/// both at any text size. The system draws a sheet taller than its detent: a
/// floating sheet runs into the home indicator's area, and a few points more
/// besides. Rather than model that, the detent learns the difference from the
/// sheet as drawn (`sheetExtra`) and gives it back. Being a type, it stays the
/// same detent as its height changes, so the coordinator's selection and the
/// comparisons against `AppSheetRoute.homeCollapsedDetent` keep matching.
nonisolated struct HomeCollapsedDetent: CustomPresentationDetent {
    nonisolated struct Measurements: Sendable {
        /// The search row, with its standard padding; see
        /// `HomeTabs.headerHeight(fieldHeight:)`.
        var headerHeight = AppSheetRoute.homeCollapsedHeight
        /// How much taller than its detent the system draws the collapsed sheet,
        /// once seen; see `sheetExtra(sheetHeight:requested:)`.
        var sheetExtra: CGFloat?
        /// The height last given to the system.
        var requested: CGFloat?
    }

    static func height(in context: Context) -> CGFloat? {
        measured.withLock { measurements in
            let height = height(measurements)
            measurements.requested = height
            return height
        }
    }

    /// Set as the sheet is laid out. Stored here rather than in the environment:
    /// the `Context` a custom detent gets doesn't carry the app's own environment
    /// values, only the system's, so one set around or in the sheet read as its
    /// default. The sheet's layout passes ask for the height again, so a
    /// measurement takes effect on the pass after it lands.
    static let measured = Mutex(Measurements())

    static func height(_ measurements: Measurements) -> CGFloat {
        collapsedHeight(headerHeight: measurements.headerHeight) - (measurements.sheetExtra ?? 0)
    }

    /// The collapsed sheet as drawn, for a header of `headerHeight`: the header,
    /// and never less than `AppSheetRoute.homeCollapsedHeight`, which the
    /// search row falls short of at most text sizes; it's centered in the
    /// extra (`HomeTabs.searchRowTopPadding`).
    static func collapsedHeight(headerHeight: CGFloat) -> CGFloat {
        max(headerHeight, AppSheetRoute.homeCollapsedHeight)
    }

    /// More than the home indicator's area and some: the sheet is being dragged.
    private static let maximumSheetExtra: CGFloat = 44

    /// How much taller than its detent the system drew the collapsed sheet, from
    /// `sheetHeight` as laid out, or `nil` when that height is the finger's
    /// rather than the system's.
    static func sheetExtra(sheetHeight: CGFloat, requested: CGFloat) -> CGFloat? {
        let extra = sheetHeight - requested
        guard extra >= 0, extra <= maximumSheetExtra else { return nil }
        return extra
    }

    /// Learns `sheetExtra` from the collapsed sheet's height as laid out, once:
    /// it's fixed for a screen, and a later measurement may be a drag's, since the
    /// detent stays collapsed until a drag settles. `forgetSheetExtra()` when the
    /// screen changes.
    static func learn(sheetHeight: CGFloat) {
        measured.withLock { measurements in
            guard measurements.sheetExtra == nil,
                  let requested = measurements.requested,
                  let extra = sheetExtra(sheetHeight: sheetHeight, requested: requested)
            else { return }
            measurements.sheetExtra = extra
        }
    }

    /// For a new screen geometry, such as a rotation, where the system's extra
    /// may differ; the next settled collapsed sheet teaches it again.
    static func forgetSheetExtra() {
        measured.withLock { $0.sheetExtra = nil }
    }
}

/// The screen's bottom edge, in window coordinates, and the safe-area inset over
/// it; see `HomeTabs.bottomClearance`.
nonisolated struct ScreenBottom: Equatable, Sendable {
    /// `nil` until measured.
    var edge: CGFloat?
    var inset: CGFloat = 0
}

extension EnvironmentValues {
    /// Whether this view is shown as a tab of the home sheet rather than as a sheet
    /// of its own. A tab has no sheet to close, so no Close button.
    @Entry var isHomeSheetTab = false

    /// Whether the home sheet lays out as tabs. Decided once, by `MapPanelRootView`
    /// from its own size class, so the sheet's tabs and the map's More button can't
    /// disagree: the sheet's trait environment need not match the screen's.
    @Entry var showsHomeTabs = true

    /// The screen's bottom, for sheet content, which ignores the safe area and so
    /// can't read it. `MapPanelRootView` sets it; see `HomeTabs.bottomClearance`.
    @Entry var screenBottom = ScreenBottom()

    /// Whether the home sheet is collapsed so far that this tab's page is hidden;
    /// see `HomeTabs.showsTabPages`. A tab stops its polling while it is.
    @Entry var isHomeSheetCollapsed = false
}

/// The home sheet's measurements that the map has to redraw for.
///
/// Observable, so a new header height, after a text size change, moves the
/// map's padding at once. `HomeCollapsedDetent.measured` holds the same height
/// for the detent, which can't read this (see there). The home sheet writes
/// both; `MapPanelRootView` owns this one and reads it.
@Observable
final class HomeSheetMetrics {
    /// The search row, with its standard padding; see
    /// `HomeTabs.headerHeight(fieldHeight:)`.
    var headerHeight = AppSheetRoute.homeCollapsedHeight

    /// The collapsed sheet as drawn.
    var collapsedHeight: CGFloat {
        HomeCollapsedDetent.collapsedHeight(headerHeight: headerHeight)
    }
}

/// The home sheet's tabs, as a row of filter chips under the search field,
/// shown once the sheet rises past collapsed. The chips grow with the text size.
struct HomeTabBar: View {
    let selection: HomeTab
    let onSelect: (HomeTab) -> Void

    /// A chip's least touch target. Its capsule is drawn 4 pt shorter at each end.
    private static let minimumRowHeight: CGFloat = 44
    private static let capsuleInset: CGFloat = 4

    /// White on it passes 4.5:1 in both appearances, which the lighter brand
    /// green does not.
    private let selectedFill = Color(uiColor: ThemeColors.shared.brandAccent)

    var body: some View {
        // Scrolls rather than squeezes: four titles don't fit every language at
        // every text size.
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    chip(tab)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .padding(.top, 4)
        .padding(.bottom, HomeTabs.chipsBottomPadding)
        .animation(.smooth(duration: 0.2), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func chip(_ tab: HomeTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            Text(tab.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color(uiColor: .label))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: Self.minimumRowHeight - 2 * Self.capsuleInset)
                .background(
                    isSelected ? AnyShapeStyle(selectedFill) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule()
                )
                .padding(.vertical, Self.capsuleInset)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// A home sheet tab page's background: the sheet's own, so the chips and the
    /// page under them sit on one surface. `TabView` gives each page an opaque white. On iOS 26 and
    /// later it's cleared, showing the sheet's Liquid Glass or, in dark mode, its
    /// opaque gray (see `searchSheetBackground()`); before, it's painted over
    /// with the sheet's gray.
    @ViewBuilder
    func tabPageBackground() -> some View {
        if #available(iOS 26.0, *) {
            background(TabPageBackgroundClearer())
        } else {
            background(Color.searchSheetBackground)
        }
    }
}

/// Clears the opaque background the home sheet's `TabView` gives a page; see
/// `tabPageBackground()`.
///
/// SwiftUI has no way to: `.background` draws over the page's white, and
/// `containerBackground(_:for: .tabView)` is unavailable on iOS. The page is a
/// hosting controller's view in a tab bar controller, so this clears every view
/// from itself up to that page.
private struct TabPageBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> ClearingView { ClearingView() }
    func updateUIView(_ uiView: ClearingView, context: Context) {}

    final class ClearingView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var path: [UIView] = []
            var view = superview
            while let current = view {
                path.append(current)
                // The page: its controller's parent is the tab bar controller.
                // Nothing is cleared unless it's found, so a change in how
                // `TabView` is built can't clear the sheet itself.
                if let controller = current.next as? UIViewController,
                   controller.parent is UITabBarController {
                    path.forEach { $0.backgroundColor = .clear }
                    return
                }
                view = current.superview
            }
        }
    }
}
