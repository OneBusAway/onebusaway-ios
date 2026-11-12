//
//  HomeTabs.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import Synchronization
import OBAKitCore

/// A tab of the home sheet on iPhone, where the panel lays its sheet out as Find
/// My does: the tabs in a bar pinned to the bottom of the sheet, over the map.
///
/// Home holds the search field and the nearby, recent and bookmarked previews the
/// sheet had before; it stands in for the classic app's Map tab, since the map is
/// always behind the sheet. Recent, Bookmarks and More are the classic app's tabs
/// of the same names, with the same titles and icons.
enum HomeTab: CaseIterable, Hashable {
    case home
    case recent
    case bookmarks
    case more

    var title: String {
        switch self {
        case .home:
            OBALoc("home_sheet.tab.home", value: "Home", comment: "Title of the map panel's Home tab, which holds search and the nearby stops. It replaces the Map tab: the map is always behind the sheet.")
        case .recent: Strings.recentTabTitle
        case .bookmarks: Strings.bookmarksTabTitle
        case .more: Strings.moreTabTitle
        }
    }

    /// Each has a `.fill` variant, which the bar draws for the selected tab.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .recent: Icons.recentTabSymbolName
        case .bookmarks: Icons.bookmarksTabSymbolName
        case .more: Icons.moreTabSymbolName
        }
    }

    /// The tab a home section's header goes to, or `nil` for a section with none,
    /// whose header still stacks its full list.
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

    /// Less room than a row under the search field and Home shows no list there.
    static let minimumListRoom: CGFloat = 44

    /// Whether Home shows its list under the search field, given the height of its
    /// page above the tab bar.
    ///
    /// Collapsed, the sheet is the search field over the bar. Whatever sliver the
    /// system leaves between them, a list peeking through it reads as cut off.
    /// Measured rather than read off the detent, so the list follows a drag rather
    /// than appearing when it settles.
    static func showsHomeList(showsTabs: Bool, pageHeight: CGFloat, searchRowHeight: CGFloat) -> Bool {
        !showsTabs || pageHeight - searchRowHeight >= minimumListRoom
    }

    /// The gap between the search field and the tab bar on the collapsed sheet,
    /// as it reads on screen.
    static let searchToTabBarSpacing: CGFloat = 8

    /// The search row's bottom padding, which the collapsed detent fits exactly.
    /// Less than `searchToTabBarSpacing`: the bar's glass capsule draws inside the
    /// top of its frame, and the search field's fill inside the bottom of its row,
    /// together about 3 pt (measured on iOS 26), so 5 pt between the frames reads
    /// as 8 between the shapes.
    static let searchRowBottomPadding: CGFloat = searchToTabBarSpacing - 3

    /// Where the sheet goes when a tab is picked, or `nil` to leave it.
    ///
    /// Collapsed, the sheet shows only the search field and the bar, so a picked
    /// tab would change nothing the rider can see. It rises to `.medium`, as Find
    /// My's does.
    static func detent(afterSelectingFrom currentDetent: PresentationDetent) -> PresentationDetent? {
        currentDetent == AppSheetRoute.homeCollapsedDetent ? .medium : nil
    }

    /// Room the bar leaves under itself for the home indicator.
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

/// The home sheet's smallest detent: the search row over the tab bar, and no more.
///
/// Fitted to the search row as laid out, measured by `HomeSheetView`, so the gap
/// over the bar is `HomeTabs.searchToTabBarSpacing` at any text size. The system
/// draws a sheet taller than its detent: a floating sheet runs into the home
/// indicator's area, and a few points more besides. Rather than model that, the
/// detent learns the difference from the sheet as drawn (`sheetExtra`) and gives
/// it back. Being a type, it stays the same detent as its height changes, so the
/// coordinator's selection and the comparisons against
/// `AppSheetRoute.homeCollapsedDetent` keep matching.
nonisolated struct HomeCollapsedDetent: CustomPresentationDetent {
    nonisolated struct Measurements: Sendable {
        /// The search row with its padding; see `AppSheetRoute.homeSearchRowHeight`.
        var searchRowHeight = AppSheetRoute.homeSearchRowHeight
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

    /// The collapsed sheet as drawn: the search row as measured over the bar.
    /// `AppSheetRoute.homeCollapsedHeight` until the row is measured.
    static var drawnHeight: CGFloat {
        measured.withLock { $0.searchRowHeight } + AppSheetRoute.homeTabBarHeight
    }

    static func height(_ measurements: Measurements) -> CGFloat {
        measurements.searchRowHeight + AppSheetRoute.homeTabBarHeight - (measurements.sheetExtra ?? 0)
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
    /// of its own. A tab has no sheet to close, so no Close button, and keeps clear
    /// of the bottom, where the tab bar is.
    @Entry var isHomeSheetTab = false

    /// Whether the home sheet lays out as tabs. Decided once, by `MapPanelRootView`
    /// from its own size class, so the sheet's tabs and the map's More button can't
    /// disagree: the sheet's trait environment need not match the screen's.
    @Entry var showsHomeTabs = true

    /// The screen's bottom, for sheet content, which ignores the safe area and so
    /// can't read it. `MapPanelRootView` sets it; see `HomeTabs.bottomClearance`.
    @Entry var screenBottom = ScreenBottom()
}

/// The bar of tabs pinned to the bottom of the home sheet: interactive Liquid
/// Glass on iOS 26, as the system tab bar is, and a material capsule before it.
struct HomeTabBar: View {
    let selection: HomeTab
    /// Room to leave under the bar for the home indicator; see
    /// `HomeTabs.bottomClearance`.
    let bottomClearance: CGFloat
    let onSelect: (HomeTab) -> Void

    private static let capsuleHeight: CGFloat = 54

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .frame(height: Self.capsuleHeight)
        .tabBarGlass()
        .padding(.horizontal, 12)
        .padding(.bottom, AppSheetRoute.homeTabBarHeight - Self.capsuleHeight + bottomClearance)
        .animation(.smooth(duration: 0.25), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        // Capped, as the system tab bar is, so the fixed-height capsule doesn't
        // clip its titles at accessibility sizes; a long press shows them large.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.body.weight(.semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// Interactive, so the bar scales and shimmers under a finger as the system
    /// tab bar does; `regularGlassEffectIfAvailable` gives static glass.
    @ViewBuilder
    func tabBarGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}

/// Clears the opaque background the home sheet's `TabView` gives each page, so
/// the sheet's Liquid Glass shows through on iOS 26 and later, as it does
/// behind the sheets without tabs.
///
/// SwiftUI has no way to: `.background` draws over the page's white, and
/// `containerBackground(_:for: .tabView)` is unavailable on iOS. The page is a
/// hosting controller's view in a tab bar controller, so this clears every view
/// from itself up to that page. Earlier systems keep the white, which
/// `Color.searchSheetBackground` paints over.
struct TabPageBackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> ClearingView { ClearingView() }
    func updateUIView(_ uiView: ClearingView, context: Context) {}

    final class ClearingView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard #available(iOS 26.0, *), window != nil else { return }
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
