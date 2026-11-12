//
//  HomeTabs.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A tab of the home sheet on iPhone, where the panel lays its sheet out as Find
/// My does: the tabs in a bar pinned to the bottom of the sheet, over the map.
///
/// Home holds the search field and the nearby, recent and bookmarked previews the
/// sheet had before; it stands in for the classic app's Map tab, since the map is
/// always behind the sheet. Recent, Bookmarks and More are the classic app's tabs
/// of the same names.
enum HomeTab: CaseIterable, Hashable {
    case home
    case recent
    case bookmarks
    case more

    /// Recent, Bookmarks and More reuse the classic tab bar's titles, which are
    /// already translated.
    var title: String {
        switch self {
        case .home:
            OBALoc("home_sheet.tab.home", value: "Home", comment: "Title of the map panel's Home tab, which holds search and the nearby stops. It replaces the Map tab: the map is always behind the sheet.")
        case .recent:
            OBALoc("recent_stops_controller.title", value: "Recent", comment: "The title of the Recent Stops controller.")
        case .bookmarks:
            OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        case .more:
            OBALoc("more_controller.title", value: "More", comment: "Title of the More tab / accessibility label for the map-panel more button.")
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .recent: "clock"
        case .bookmarks: "bookmark"
        case .more: "ellipsis"
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

    /// Whether Home shows its list under the search field. Not on the collapsed
    /// sheet with tabs, which is the search field over the bar: whatever room the
    /// system leaves between them, a list peeking through it reads as cut off.
    static func showsHomeList(showsTabs: Bool, currentDetent: PresentationDetent) -> Bool {
        !showsTabs || currentDetent != .height(AppSheetRoute.homeCollapsedHeight)
    }

    /// Where the sheet goes when a tab is picked, or `nil` to leave it.
    ///
    /// Collapsed, the sheet shows only the search field and the bar, so a picked
    /// tab would change nothing the rider can see. It rises to `.medium`, as Find
    /// My's does.
    static func detent(afterSelecting tab: HomeTab, currentDetent: PresentationDetent) -> PresentationDetent? {
        currentDetent == .height(AppSheetRoute.homeCollapsedHeight) ? .medium : nil
    }
}

/// The bar of tabs pinned to the bottom of the home sheet: Liquid Glass on iOS 26,
/// a material capsule before it.
struct HomeTabBar: View {
    @Binding var selection: HomeTab
    let onSelect: (HomeTab) -> Void

    /// The bar's capsule and the padding under it. Part of the home sheet's
    /// collapsed height, so the collapsed sheet is exactly the search row and this.
    nonisolated static let height: CGFloat = capsuleHeight + bottomPadding

    private nonisolated static let capsuleHeight: CGFloat = 54
    private nonisolated static let bottomPadding: CGFloat = 8

    @Namespace private var namespace

    private static var homeIndicatorClearance: CGFloat {
        UIApplication.shared.keyWindowFromScene?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .frame(height: Self.capsuleHeight)
        .regularGlassEffectIfAvailable(in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, Self.bottomPadding)
        // The sheet's content reaches into the home indicator's area, but a
        // `.height` detent is measured above it. Clear of it, the bar sits where
        // `height` says, and the collapsed sheet is exactly the search row and this.
        .padding(.bottom, Self.homeIndicatorClearance)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        let isSelected = tab == selection
        return Button {
            selection = tab
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.smooth(duration: 0.25), value: selection)
    }
}
