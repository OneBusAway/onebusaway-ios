//
//  HomeSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import TipKit
import OBAKitCore

/// The panel's base sheet. On iPhone it carries tabs, Find My style: Home (search
/// and the nearby, recent and bookmarked previews), Recent, Bookmarks and More, in
/// a bar pinned to its bottom. See `HomeTab`.
struct HomeSheetView: View {
    @StateObject private var viewModel: HomeSheetViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.scenePhase) private var scenePhase
    /// See `EnvironmentValues.showsHomeTabs`.
    @Environment(\.showsHomeTabs) private var showsTabs

    /// See `HomeTabs.bottomClearance`.
    @Environment(\.screenBottom) private var screenBottom
    @State private var barClearance: CGFloat = 0

    @State private var selectedTab: HomeTab = .home
    /// Home's page above the tab bar; see `HomeTabs.showsHomeList`.
    @State private var homePageHeight: CGFloat = 0
    /// The search row as measured, for `showsHomeList`. Mirrors
    /// `HomeCollapsedDetent.measured`, which the detent reads but which, being a
    /// lock rather than state, doesn't redraw this view.
    @State private var searchRowHeight = AppSheetRoute.homeSearchRowHeight

    /// Used by the bookmark rows to format distances.
    private let application: Application

    /// Opens a service alert's detail.
    private let onSelectAlert: (AgencyAlert) -> Void

    init(
        application: Application,
        viewModel: @autoclosure @escaping () -> HomeSheetViewModel,
        onSelectAlert: @escaping (AgencyAlert) -> Void = { _ in }
    ) {
        self.application = application
        self.onSelectAlert = onSelectAlert
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    /// What's on screen. Regular width has no tabs, so always Home.
    private var visibleTab: HomeTab {
        showsTabs ? selectedTab : .home
    }

    private var isShowingHomePage: Bool {
        coordinator.stackedRoutes.isEmpty && visibleTab == .home
    }

    var body: some View {
        // The bar under the tabs rather than in a `safeAreaInset` over them:
        // `TabView` lays its pages out beneath an inset, which put Home's list
        // behind the bar.
        VStack(spacing: 0) {
            tabs
            if showsTabs {
                HomeTabBar(
                    selection: selectedTab,
                    bottomClearance: barClearance,
                    onSelect: select(_:)
                )
            }
        }
            // Reduced to the clearance in the transform, so a drag, which moves
            // the sheet every frame, redraws this view only when the clearance
            // changes.
            .onGeometryChange(for: CGFloat.self) { [screenBottom] proxy in
                HomeTabs.bottomClearance(sheetBottom: proxy.frame(in: .global).maxY, screen: screenBottom)
            } action: { barClearance = $0 }
            // On the whole sheet, not just the pages: the bar sits on it, and More,
            // a UIKit host, sets no sheet background of its own.
            .searchSheetBackground()
            .task(id: isShowingHomePage) {
                // Polls while Home is on screen, so bookmark countdowns don't
                // freeze, and refreshes the moment it comes back: from a stacked
                // sheet, when a recent stop may have been added, or from another
                // tab. `loadIfNeeded`'s staleness gate keeps it to one fetch per
                // window however often this fires.
                guard isShowingHomePage else { return }
                while !Task.isCancelled {
                    viewModel.activate()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // A phone unlocked after twenty minutes would otherwise show the
                // countdowns it had when it locked — "NOW" for a bus long gone.
                if phase == .active && isShowingHomePage {
                    viewModel.activate()
                }
            }
    }

    /// The tabs, in a `TabView` whose own bar is hidden for `HomeTabBar`. It
    /// builds each tab the first time it's picked and keeps it after, so leaving a
    /// tab and coming back keeps its scroll position, search text and More's pushed
    /// screens, and exposes only the visible tab to VoiceOver. Regular width has no
    /// tabs, so just Home.
    @ViewBuilder
    private var tabs: some View {
        if showsTabs {
            TabView(selection: $selectedTab) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    tabContent(tab)
                        // The sheet's own background, which the bar sits on:
                        // the pages' default white left a seam where the bar
                        // began.
                        .tabPageBackground()
                        .environment(\.isHomeSheetTab, tab != .home)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
        } else {
            homePage
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: HomeTab) -> some View {
        switch tab {
        case .home:
            homePage
        case .recent:
            RecentStopsSheetView(application: application)
        case .bookmarks:
            BookmarksSheetView(application: application)
        case .more:
            MoreSheetHost(application: application)
        }
    }

    private func select(_ tab: HomeTab) {
        selectedTab = tab
        if let detent = HomeTabs.detent(afterSelectingFrom: coordinator.currentDetent) {
            coordinator.currentDetent = detent
        }
    }

    /// A section header's index: its tab where there is one, otherwise the full
    /// list stacked over the sheet.
    private func showAll(_ route: AppSheetRoute) {
        if showsTabs, let tab = HomeTab(seeAll: route) {
            select(tab)
        } else {
            coordinator.push(route)
        }
    }

    // MARK: - Home

    private var homePage: some View {
        VStack(spacing: 0) {
            searchBarRow
                .padding(.top, 16)
                .padding(.bottom, HomeTabs.searchRowBottomPadding)
                // Its own height, however short the page: measured for the
                // collapsed detent, a squeezed row would shrink the detent, which
                // would squeeze it further.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    searchRowHeight = height
                    HomeCollapsedDetent.measured.withLock { $0.searchRowHeight = height }
                }

            if !HomeTabs.showsHomeList(showsTabs: showsTabs, pageHeight: homePageHeight, searchRowHeight: searchRowHeight) {
                Spacer()
            } else if !viewModel.visibleSections.isEmpty {
                List {
                    ForEach(viewModel.visibleSections, id: \.self) { section in
                        sectionContent(for: section)
                    }
                }
                // Applied to the `List`, matching `BookmarksListView`, rather than
                // to the bookmarks `Section` alone.
                .environment(\.obaFormatters, application.formatters)
                .searchListChrome()
            } else if viewModel.hasLoadedInitialContent {
                emptyState
            } else {
                // Pre-first-settle: nearby hasn't had its chance yet, so "empty"
                // isn't a fact. Hold the space rather than flash a wrong answer.
                Spacer()
            }
        }
        // With the tab bar, stops at it: drawn under the glass, the list and the
        // empty state showed through the bar on the collapsed sheet. Clipped, as
        // the empty state is taller than the room the collapsed sheet leaves.
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { homePageHeight = $0 }
        .searchSheetBackground()
        .ignoresSafeArea(.container, edges: showsTabs ? [] : .bottom)
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        Button {
            coordinator.push(.search)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(viewModel.searchPlaceholder)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background { Capsule().fill(Color(.tertiarySystemFill)) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        // The map panel's home for `TripPlannerTip`, which on the UIKit surface
        // points at `MapFloatingPanelController`'s search bar — this row is that
        // bar's counterpart, and the tip's copy ("tap here to search for places")
        // only reads correctly anchored to it. `popoverTip` rather than
        // `TipPresenter`: the UIKit presenter exists to work around a broken
        // system *controller*, and none of that applies here.
        //
        // Passing `nil` when the region has no OTP server withholds the tip
        // instead of spending its one display announcing a feature the rider
        // cannot reach.
        //
        // Withheld, too, while another tab is showing: the page is still in the
        // hierarchy, hidden, and the tip would both pop up over that tab and
        // leave this field reachable by VoiceOver.
        .popoverTip(viewModel.offersTripPlanning && visibleTab == .home ? TripPlannerTip() : nil)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionContent(for section: HomeSheetSection) -> some View {
        switch section {
        case .alerts:
            alertsSection

        case .nearby:
            stopSection(
                stops: viewModel.nearby.stops,
                title: Strings.nearbyStops,
                seeAll: .nearbyAll
            )

        case .recent:
            stopSection(
                stops: viewModel.recent.stops,
                title: Strings.recentStops,
                seeAll: .recentStopsAll,
                alarmCount: viewModel.recent.alarmCount
            )

        case .bookmarks:
            bookmarksSection
        }
    }

    /// The nearby and recent sections: same row and header shape, different
    /// source and destination.
    private func stopSection(
        stops: [Stop],
        title: String,
        seeAll: AppSheetRoute,
        alarmCount: Int = 0
    ) -> some View {
        Section {
            // The Recent index lists alarms, as the Recent tab does. This row is
            // the way to them, and is all the section has with no recent stops.
            if alarmCount > 0 {
                Button {
                    showAll(seeAll)
                } label: {
                    LabeledContent {
                        Text(alarmCount, format: .number)
                    } label: {
                        Label(RecentStopsSheetView.alarmsTitle, systemImage: "alarm")
                    }
                }
                .foregroundStyle(Color(uiColor: .label))
            }
            ForEach(stops, id: \.id) { stop in
                HomeStopRow(stop: stop) {
                    coordinator.push(.stopDetails(stopID: stop.id))
                }
            }
        } header: {
            HomeSectionHeader(title: title) {
                showAll(seeAll)
            }
        }
        .textCase(nil)
    }

    /// No index to open, so the header is a plain title rather than a
    /// `HomeSectionHeader` button.
    private var alertsSection: some View {
        Section {
            ForEach(viewModel.alerts.alerts) { alert in
                Button {
                    onSelectAlert(alert)
                } label: {
                    Label {
                        Text(alert.title(forLocale: application.locale) ?? Strings.serviceAlerts)
                            .foregroundStyle(Color(uiColor: .label))
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text(Strings.serviceAlerts)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color(uiColor: .label))
                .accessibilityAddTraits(.isHeader)
        }
        .textCase(nil)
    }

    /// Bookmark rows reuse the Bookmarks tab's cells as-is, so the two surfaces
    /// can't drift apart visually.
    private var bookmarksSection: some View {
        Section {
            ForEach(viewModel.bookmarks.rows) { row in
                Group {
                    if row.isTripBookmark {
                        BookmarkCardView(row: row)
                    } else {
                        StopBookmarkRow(row: row)
                    }
                }
                .contentShape(.rect)
                .onTapGesture {
                    coordinator.push(.stopDetails(stopID: row.stopID))
                }
                // The cells announce `.isButton`; `.onTapGesture` is invisible to
                // assistive tech, so the default action carries the same tap.
                .accessibilityAction {
                    coordinator.push(.stopDetails(stopID: row.stopID))
                }
                .contextMenu {
                    // Pinning is reachable from the row it affects, not only from
                    // the Bookmarks tab — this section is where the result shows.
                    BookmarkPinButton(isPinned: row.isPinned) {
                        viewModel.bookmarks.togglePin(row.bookmark)
                    }
                }
            }
        } header: {
            HomeSectionHeader(title: Strings.bookmarks) {
                showAll(.bookmarksAll)
            }
        }
        .textCase(nil)
    }

    /// Shown only when all three sections are empty at once — a first launch, or
    /// a map parked at region-level zoom with nothing saved.
    ///
    /// Has its own copy rather than reusing the nearby controller's: two of the
    /// three sections have nothing to do with the map, so "Zoom out or pan around
    /// to find some stops" would be advice that can't fix what the user is
    /// actually missing.
    ///
    /// Deliberately omits the nearby controller's "Search Wider Area" button: that
    /// drives `MapRegionManager.preferredLoadDataRegionFudgeFactor` and a timed
    /// reset the SwiftUI path has no equivalent plumbing for.
    private var emptyState: some View {
        EmptyStateView(
            title: OBALoc(
                "home_sheet.empty_set.title",
                value: "Nothing Here Yet",
                comment: "Title for the home sheet's empty state, shown when there are no nearby stops, no recent stops, and no bookmarks."
            ),
            description: OBALoc(
                "home_sheet.empty_set.body",
                value: "Nearby stops, stops you've viewed, and your bookmarks will show up here.",
                comment: "Body for the home sheet's empty state, shown when there are no nearby stops, no recent stops, and no bookmarks."
            ),
            systemImage: "mappin.slash"
        )
        .padding(.top, 40)
    }
}
