//
//  HomeTabs.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Synchronization
import OBAKitCore

/// A tab of the home sheet on iPhone, in the tab bar under the search field
/// (`HomeTabBar`), which shows at every detent, collapsed included (#1750).
///
/// Home is the mixed view: bookmarks, what leaves nearby, recent stops and
/// shortcuts. Recent and Bookmarks are its sections at full length, so a
/// section's header and its tab lead to the same place. Nearby has no tab: its
/// content is on Home, and its header stacks the full list. More, a tab of the
/// classic app, is a row in Home's Settings and More section.
enum HomeTab: CaseIterable, Hashable {
    case home
    case recent
    case bookmarks

    var title: String {
        switch self {
        case .home:
            OBALoc("home_sheet.tab.home", value: "Home", comment: "Title of the first tab on the map panel's home sheet: the mixed view of the rider's bookmarks, departures from nearby stops, and recent stops. Short: it is one of three tabs, under an icon.")
        case .recent: Strings.recentTabTitle
        case .bookmarks: Strings.bookmarksTabTitle
        }
    }

    /// Drawn above the title.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .recent: "clock"
        case .bookmarks: "bookmark"
        }
    }

    /// For UI tests, which can't match on the localized title.
    var accessibilityIdentifier: String {
        switch self {
        case .home: "home_tab_home"
        case .recent: "home_tab_recent"
        case .bookmarks: "home_tab_bookmarks"
        }
    }

    /// The tab a home section's header goes to, or `nil` for a route that is no
    /// tab's index.
    init?(seeAll route: AppSheetRoute) {
        switch route {
        case .recentStopsAll: self = .recent
        case .bookmarksAll: self = .bookmarks
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

    /// Less room than a row under the tab bar and no tab shows its page there.
    /// `nonisolated`, like `showsTabPages`, for `onGeometryChange`'s transform,
    /// which runs off the main actor.
    nonisolated static let minimumListRoom: CGFloat = 44

    /// Whether the tabs' pages show under the tab bar, given the height of the
    /// pages' area.
    ///
    /// Collapsed, the sheet is the search field over the tab bar, whichever tab
    /// is picked: the detent fits those two rows and no more, and every tab hides
    /// its page. Whatever sliver the system leaves, a page peeking through it
    /// reads as cut off. Measured rather than read off the detent, so the pages
    /// follow a drag rather than appearing when it settles.
    nonisolated static func showsTabPages(showsTabs: Bool, pageHeight: CGFloat) -> Bool {
        !showsTabs || pageHeight >= minimumListRoom
    }

    /// Whether a page's 30-second poll runs: only while the rider can see the page.
    /// Not when a stacked sheet covers it, and not when the home sheet is collapsed
    /// and the page is hidden (see `showsTabPages`).
    static func shouldPoll(isOnScreen: Bool, isCovered: Bool, isCollapsed: Bool) -> Bool {
        isOnScreen && !isCovered && !isCollapsed
    }

    /// Under the search field, over the tab bar.
    nonisolated static let searchRowBottomPadding: CGFloat = 4

    /// Above the search field, at every detent.
    nonisolated static let searchRowTopPadding: CGFloat = 16

    /// Under the tab bar, before the page's own top margin.
    static let tabBarBottomPadding: CGFloat = 4

    /// Between the sheet's sides and everything on it: the search field, the tab
    /// bar, and Home's content, which lines up with the two.
    static let horizontalMargin: CGFloat = 12

    /// The header the collapsed detent is fitted to: the search field with its
    /// padding, the tab bar (`tabBarHeight`, its padding included; zero without
    /// tabs), and `accessoryHeight` for a row under the tabs. Nothing fills that
    /// row yet; a next-departure row there would grow the collapsed sheet by its
    /// own height and need no other change (#1750).
    nonisolated static func headerHeight(fieldHeight: CGFloat, tabBarHeight: CGFloat, accessoryHeight: CGFloat = 0) -> CGFloat {
        searchRowTopPadding + fieldHeight + searchRowBottomPadding + tabBarHeight + accessoryHeight
    }

    /// Where the sheet goes when a tab is picked, or `nil` to leave it.
    ///
    /// Collapsed, the sheet shows only the search field and the tab bar, so a
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

/// The home sheet's smallest detent: the search row and the tab bar, and no more.
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
        /// The search row and the tab bar; see `HomeTabs.headerHeight`.
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
    ///
    /// One per process, not per scene: `height(in:)` gets no scene or window
    /// identity to key it by. On iPad with two windows, each window's home sheet
    /// writes `headerHeight`, `requested` and `sheetExtra` here, and each sheet's
    /// detent reads whichever window wrote last. They agree while the windows'
    /// headers lay out alike; they can disagree when the windows differ in
    /// horizontal size class (tabs in one, none in the other), Dynamic Type, or
    /// screen geometry (`sheetExtra`, e.g. one window in Slide Over or on an
    /// external display). The effect is a collapsed detent sized for the other
    /// window until this window's header publishes again, which happens only
    /// when its height changes (a resize, size-class or text-size change) or the
    /// sheet is built anew; a layout pass alone doesn't. Accepted for 26.5 as
    /// cosmetic.
    static let measured = Mutex(Measurements())

    static func height(_ measurements: Measurements) -> CGFloat {
        collapsedHeight(headerHeight: measurements.headerHeight) - (measurements.sheetExtra ?? 0)
    }

    /// The collapsed sheet as drawn, for a header of `headerHeight`: the header,
    /// and never less than `AppSheetRoute.homeCollapsedHeight`, a floor for the
    /// iOS 26 short-sheet behaviour. The header is laid out at its standard
    /// padding from the top; any extra falls under it.
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
    /// The search row and the tab bar; see `HomeTabs.headerHeight`.
    var headerHeight = AppSheetRoute.homeCollapsedHeight

    /// The collapsed sheet as drawn.
    var collapsedHeight: CGFloat {
        HomeCollapsedDetent.collapsedHeight(headerHeight: headerHeight)
    }
}

/// The home sheet's tab bar: Home, Recent and Bookmarks, each an icon above
/// its title, under the search field at every detent (#1750). Its own view,
/// apart from the search field, so a row can go between it and the pages.
///
/// The selected tab is drawn in the brand accent on a light brand tint, and
/// in a heavier weight, so it doesn't rely on colour alone. The tabs share the
/// width equally and grow with the text size; at accessibility sizes the
/// titles may wrap to two lines rather than truncate.
struct HomeTabBar: View {
    let selection: HomeTab
    let onSelect: (HomeTab) -> Void

    /// A tab's least touch target.
    private static let minimumHeight: CGFloat = 44

    /// See `highlight(in:)`.
    private static let highlightCornerRadius: CGFloat = 12

    /// The tab bar's own coordinates, which `SheetCornerTracker` reports the
    /// sheet in and the highlight measures itself in.
    private static let coordinateSpace = "HomeTabBar"

    /// The sheet's frame and corner radius; see `SheetCornerTracker`. `nil`
    /// before iOS 26, or until read.
    @State private var sheetCorners: SheetCornerGeometry?

    @Environment(\.layoutDirection) private var layoutDirection

    /// The selected tab's highlight, at `frame` in the tab bar. Each corner
    /// near one of the sheet's is concentric with it, as the sheet's own corners
    /// are with the screen's: collapsed, Home's and Bookmarks' outer bottom
    /// corners follow the sheet's curve. The rest keep the 12-point radius. See
    /// `HomeTabs.highlightCornerRadii`.
    ///
    /// Worked out here rather than left to `ConcentricRectangle`, which tried
    /// it and drew every corner at its minimum, or at a radius that didn't
    /// match the sheet, depending on how it was built.
    private func highlight(in frame: CGRect) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: HomeTabs.highlightCornerRadii(
                highlight: frame,
                sheet: sheetCorners,
                minimum: Self.highlightCornerRadius,
                layoutDirection: layoutDirection
            ),
            style: .continuous
        )
        .fill(tint)
    }

    /// `#486621` in light mode: legible as text on the light tint below, which
    /// the lighter brand green is not. In dark mode the dark brand accent falls
    /// short of 4.5:1 on the sheet, so the lighter brand green takes over there.
    private let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ThemeColors.shared.brand : ThemeColors.shared.brandAccent
    })
    private let tint = Color(uiColor: ThemeColors.shared.brand).opacity(0.16)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        // The same frame as the coordinate space above, so the two compare.
        .background {
            SheetCornerTracker { sheetCorners = $0 }
        }
        .padding(.horizontal, HomeTabs.horizontalMargin)
        .padding(.top, 4)
        .padding(.bottom, HomeTabs.tabBarBottomPadding)
        .animation(.smooth(duration: 0.2), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? "\(tab.systemImage).fill" : tab.systemImage)
                    .font(.body.weight(.semibold))
                    .imageScale(.medium)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? accent : Color(uiColor: .label))
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                GeometryReader { proxy in
                    highlight(in: proxy.frame(in: .named(Self.coordinateSpace)))
                }
            }
        }
        // Read as a tab, "selected" or not, inside the tab bar container above.
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }
}

/// A sheet's frame and corner radius, in the coordinates of a view inside it.
nonisolated struct SheetCornerGeometry: Equatable, Sendable {
    var frame: CGRect
    var radius: CGFloat
}

extension HomeTabs {
    /// The selected tab highlight's corners: each concentric with the sheet's
    /// nearest corner where it is close enough to one to follow its curve, and
    /// never less than `minimum`.
    ///
    /// Concentric means the sheet's radius less the distance between the two
    /// shapes' edges, as the sheet's own corners are inset from the screen's.
    /// Where the two edges are unequally far apart, the larger distance counts,
    /// which keeps the curve inside the sheet's. A corner farther from the
    /// sheet's than its radius gets `minimum`: on the collapsed sheet, every
    /// corner but the outer tabs' bottom outer ones, and at taller detents all
    /// of them. Without `sheet`, all corners are `minimum`.
    ///
    /// The frames are laid out left to right whatever the language; in a
    /// right-to-left layout the leading corners are the right-hand ones.
    nonisolated static func highlightCornerRadii(
        highlight: CGRect,
        sheet: SheetCornerGeometry?,
        minimum: CGFloat,
        layoutDirection: LayoutDirection
    ) -> RectangleCornerRadii {
        guard let sheet, sheet.radius > 0 else {
            return RectangleCornerRadii(topLeading: minimum, bottomLeading: minimum, bottomTrailing: minimum, topTrailing: minimum)
        }
        let outer = sheet.frame
        func radius(_ horizontalInset: CGFloat, _ verticalInset: CGFloat) -> CGFloat {
            max(minimum, sheet.radius - max(horizontalInset, verticalInset, 0))
        }
        let top = highlight.minY - outer.minY
        let bottom = outer.maxY - highlight.maxY
        let left = highlight.minX - outer.minX
        let right = outer.maxX - highlight.maxX
        let (leading, trailing) = layoutDirection == .rightToLeft ? (right, left) : (left, right)
        return RectangleCornerRadii(
            topLeading: radius(leading, top),
            bottomLeading: radius(leading, bottom),
            bottomTrailing: radius(trailing, bottom),
            topTrailing: radius(trailing, top)
        )
    }
}

/// Keeps `SheetCornerReader` current as the sheet is dragged, in a view of its
/// own so a drag redraws only this. The tab bar redraws only when the reported
/// geometry changes, which `SheetCornerReader` keeps to drags near the
/// collapsed detent, where a corner follows the sheet.
private struct SheetCornerTracker: View {
    let onChange: (SheetCornerGeometry?) -> Void

    /// Where this is on screen: it moves as the sheet is dragged, and a change
    /// has the reader read the sheet again.
    @State private var screenFrame: CGRect = .zero

    var body: some View {
        SheetCornerReader(refreshTrigger: screenFrame, onChange: onChange)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screenFrame = $0 }
    }
}

/// Reports the frame and corner radius of the sheet it's in, in its own
/// coordinates: the nearest view above it with rounded corners, by
/// `UIView.effectiveRadius(corner:)` (iOS 26). Reports `nil` before iOS 26,
/// where the sheet's corners are fixed and plain.
///
/// Read again whenever its own layout changes, and whenever `refreshTrigger`
/// does, which it doesn't use but which changes as the sheet is dragged.
private struct SheetCornerReader: UIViewRepresentable {
    let refreshTrigger: CGRect
    let onChange: (SheetCornerGeometry?) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onChange = onChange
        uiView.read()
    }

    final class ReaderView: UIView {
        var onChange: ((SheetCornerGeometry?) -> Void)?
        private var lastReported: SheetCornerGeometry??

        override func didMoveToWindow() {
            super.didMoveToWindow()
            read()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            read()
        }

        func read() {
            guard window != nil else { return }
            let geometry = sheetGeometry()
            guard lastReported != .some(geometry) else { return }
            lastReported = .some(geometry)
            // Not during SwiftUI's update, which this is called from.
            DispatchQueue.main.async { [onChange] in onChange?(geometry) }
        }

        private func sheetGeometry() -> SheetCornerGeometry? {
            guard #available(iOS 26.0, *),
                  let sheet = ancestors.first(where: { $0.effectiveRadius(corner: [.bottomLeft, .bottomRight]) > 0 })
            else { return nil }
            let radius = sheet.effectiveRadius(corner: [.bottomLeft, .bottomRight])
            return SheetCornerGeometry(frame: clamped(sheet.convert(sheet.bounds, to: self), reach: radius), radius: radius)
        }

        /// `frame` with an edge farther from these bounds than `reach` pulled
        /// in to just past it: no corner that far off is rounded by it, and a
        /// sheet dragged at a taller detent then reports no change at all.
        private func clamped(_ frame: CGRect, reach: CGFloat) -> CGRect {
            let minY = max(frame.minY, bounds.minY - reach - 1)
            let maxY = min(frame.maxY, bounds.maxY + reach + 1)
            return CGRect(x: frame.minX, y: minY, width: frame.width, height: max(0, maxY - minY))
        }
    }
}

private extension UIView {
    /// This view's superviews, nearest first, short of the window.
    var ancestors: some Sequence<UIView> {
        sequence(first: superview, next: { $0?.superview })
            .prefix { $0 != nil && !($0 is UIWindow) }
            .compactMap { $0 }
    }
}

extension View {
    /// A home sheet tab page's background: the sheet's own, so the tab bar and the
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

// MARK: - Insets

/// Lines Home's content up with the search field and tab bar, which sit
/// `HomeTabs.horizontalMargin` from the sheet's sides, as the list's cards do.
/// The Recent tab's list uses them too, so its rows sit where Home's do.
extension View {
    /// A section header, on the cards' edges, with no inset of its own.
    @ViewBuilder
    func homeHeaderInsets() -> some View {
        if #available(iOS 26.0, *) {
            listRowInsets(.horizontal, 0)
        } else {
            self
        }
    }

    /// A row: on the cards' edges where the cards don't show, on the sheet's
    /// glass, where their usual inset would leave the text indented past the
    /// search field. Where they show, the text keeps its inset inside them.
    func homeRowInsets() -> some View {
        modifier(HomeRowInsets())
    }
}

private struct HomeRowInsets: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // `nil` is the list's own inset.
            content.listRowInsets(.horizontal, colorScheme.showsSheetGlass ? 0 : nil)
        } else {
            content
        }
    }
}
