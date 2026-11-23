//
//  HomeSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import TipKit
import OBAKitCore

/// The panel's base sheet: the search field, over the Home / Recent / Bookmarks
/// tab bar on iPhone. Collapsed, it's those two rows, sized to them (#1750).
/// Home, the first tab, is the mixed view: bookmark cards, what leaves from
/// nearby stops, recent stops, a row of shortcuts, and last the ways into
/// the map's options, settings and More. See `HomeTab`.
struct HomeSheetView: View {
    @StateObject private var viewModel: HomeSheetViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    /// See `EnvironmentValues.showsHomeTabs`.
    @Environment(\.showsHomeTabs) private var showsTabs

    /// See `HomeTabs.bottomClearance`.
    @Environment(\.screenBottom) private var screenBottom
    /// Room the pages leave at their bottom for the home indicator.
    @State private var bottomClearance: CGFloat = 0

    @State private var selectedTab: HomeTab = .home
    /// Whether the tabs' pages show under the tab bar; see `HomeTabs.showsTabPages`.
    /// Kept as the Bool rather than the measured height, so a drag, which changes
    /// the height every frame, redraws this view only when it flips.
    @State private var showsPages = true
    /// The search field's height, without its padding; see `HomeTabs.headerHeight`.
    @State private var searchFieldHeight: CGFloat = 0
    /// The tab bar's height with its padding; zero without tabs.
    @State private var tabBarHeight: CGFloat = 0
    /// Whether More offers a donate option, once the storefront has answered
    /// since launch; `nil` until then, when `donationsEnabled` is read live.
    /// `DonationsManager` isn't observable, so this is what redraws the More
    /// row's subtitle when the answer changes.
    @State private var offersDonations: Bool?
    /// The map reads the header's height from here; see `HomeSheetMetrics`.
    /// `nil` outside the map panel.
    @Environment(HomeSheetMetrics.self) private var metrics: HomeSheetMetrics?

    /// Used by the bookmark rows to format distances.
    private let application: Application

    /// Opens a service alert's detail.
    private let onSelectAlert: (AgencyAlert) -> Void

    /// Presents the app's settings.
    private let onOpenSettings: () -> Void

    init(
        application: Application,
        viewModel: @autoclosure @escaping () -> HomeSheetViewModel,
        onSelectAlert: @escaping (AgencyAlert) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.application = application
        self.onSelectAlert = onSelectAlert
        self.onOpenSettings = onOpenSettings
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    /// What's on screen. Regular width has no tabs, so always Home.
    private var visibleTab: HomeTab {
        showsTabs ? selectedTab : .home
    }

    /// Home's poll runs while Home is picked and nothing is stacked over it, even
    /// collapsed, where its list is hidden: the poll is what refreshes the
    /// bookmark widget and running Live Activities (`HomeBookmarksSectionModel`),
    /// and collapsed is the home sheet's resting state.
    private var isPollingHome: Bool {
        HomeTabs.shouldPoll(
            isOnScreen: visibleTab == .home,
            isCovered: !coordinator.stackedRoutes.isEmpty,
            isCollapsed: false
        )
    }

    /// Whether Home's list is on screen, which is when its Nearby section
    /// may fetch arrivals: unlike the bookmarks' poll, nothing off screen needs
    /// them.
    private var isHomeListVisible: Bool {
        isPollingHome && showsPages
    }

    var body: some View {
        // The search row and tab bar over the pages rather than in a
        // `safeAreaInset`: `TabView` lays its pages out beneath an inset.
        VStack(spacing: 0) {
            header
                // The header keeps its height on the collapsed sheet, which is
                // fitted to it; the pages take what's left, down to nothing.
                .layoutPriority(1)
            tabs
                // Clipped: a page hidden on the collapsed sheet may still be
                // taller than the room it leaves.
                .frame(minHeight: 0, alignment: .top)
                .clipped()
                // Reduced to the Bool in the transform, like the clearance below.
                .onGeometryChange(for: Bool.self) { [showsTabs] proxy in
                    HomeTabs.showsTabPages(showsTabs: showsTabs, pageHeight: proxy.size.height)
                } action: { showsPages = $0 }
                // The pages reach the sheet's bottom edge, and sheet content
                // can't read the safe area there; see `HomeTabs.bottomClearance`.
                .contentMargins(.bottom, bottomClearance, for: .scrollContent)
        }
            // From the top, at whatever height the sheet offers. The collapsed
            // sheet offers less than the header, which it draws past its detent
            // (`HomeCollapsedDetent`); without the minimum this frame would grow
            // to the header and be centred, lifting the search field over the
            // grabber.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            // Reduced to the clearance in the transform, so a drag, which moves
            // the sheet every frame, redraws this view only when the clearance
            // changes.
            .onGeometryChange(for: CGFloat.self) { [screenBottom] proxy in
                HomeTabs.bottomClearance(sheetBottom: proxy.frame(in: .global).maxY, screen: screenBottom)
            } action: { bottomClearance = $0 }
            // On the whole sheet, not just the pages: the tab bar sits on it. A no-op
            // where the sheet's Liquid Glass is the background (iOS 26, light mode).
            .searchSheetBackground()
            .ignoresSafeArea(.container, edges: showsTabs ? [] : .bottom)
            .onReceive(application.notificationCenter.publisher(for: .donationsEligibilityDidChange)) { _ in
                offersDonations = application.donationsManager.donationsEnabled
            }
            .onChange(of: showsTabs, initial: true) {
                // The tab bar comes and goes with the tabs, and leaving takes no
                // geometry change with it to republish the header without it.
                publishHeaderHeight()
            }
            .onChange(of: isHomeListVisible, initial: true) { _, isVisible in
                viewModel.nearbyDepartures.isVisible = isVisible
            }
            .task(id: isPollingHome) {
                // Polls while Home is the tab on screen, so bookmark countdowns
                // don't freeze, and refreshes the moment it comes back: from a
                // stacked sheet, when a recent stop may have been added, or from
                // another tab. `loadIfNeeded`'s staleness gate keeps it to one
                // fetch per window however often this fires.
                guard isPollingHome else { return }
                while !Task.isCancelled {
                    viewModel.activate()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // A phone unlocked after twenty minutes would otherwise show the
                // countdowns it had when it locked — "NOW" for a bus long gone.
                if phase == .active && isPollingHome {
                    viewModel.activate()
                }
            }
    }

    /// The search row and the tab bar, which the collapsed detent is fitted to,
    /// laid out at their standard padding from the top at every detent.
    ///
    /// A row for the collapsed sheet (the next departure at a top bookmark, say)
    /// would go between the tab bar and the pages, with its height added to
    /// `HomeTabs.headerHeight`'s `accessoryHeight`.
    private var header: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                // Its own height, however short the sheet: a squeezed field would
                // shrink the detent measured from it, which would squeeze it further.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    searchFieldHeight = height
                    publishHeaderHeight()
                }
                .padding(.top, HomeTabs.searchRowTopPadding)
                .padding(.bottom, HomeTabs.searchRowBottomPadding)
            if showsTabs {
                tabBar
            }
        }
        .frame(maxWidth: .infinity)
        .background(pageBackground)
    }

    /// The tabs, under the search row at every detent: tapping one on the
    /// collapsed sheet raises it to `.medium` (`HomeTabs.detent(afterSelectingFrom:)`).
    private var tabBar: some View {
        HomeTabBar(selection: selectedTab, onSelect: select(_:))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                tabBarHeight = height
                publishHeaderHeight()
            }
    }

    /// The map's copy of the header height, and the detent's, which can't read
    /// the map's.
    private func publishHeaderHeight() {
        let headerHeight = HomeTabs.headerHeight(
            fieldHeight: searchFieldHeight,
            tabBarHeight: showsTabs ? tabBarHeight : 0
        )
        metrics?.headerHeight = headerHeight
        HomeCollapsedDetent.measured.withLock { $0.headerHeight = headerHeight }
    }

    /// Behind the header and each tab's page where the sheet shows its glass.
    /// `TabView` gives a page an opaque background there that
    /// `tabPageBackground()` doesn't always clear, which left a seam under the
    /// tab bar: glass over it, white under. Painted, the two can't differ.
    private var pageBackground: Color {
        showsTabs && colorScheme.showsSheetGlass ? Color(.systemBackground) : .clear
    }

    /// The tabs, in a `TabView` whose own bar is hidden for `HomeTabBar`. It
    /// builds each tab the first time it's picked and keeps it after, so leaving a
    /// tab and coming back keeps its scroll position and search text, and exposes
    /// only the visible tab to VoiceOver. Regular width has no tabs, so just Home.
    @ViewBuilder
    private var tabs: some View {
        if showsTabs {
            TabView(selection: $selectedTab) {
                ForEach(HomeTab.allCases, id: \.self) { tab in
                    // Hidden on the collapsed sheet rather than removed, so each
                    // keeps its state for when the sheet rises.
                    tabContent(tab)
                        .opacity(showsPages ? 1 : 0)
                        .allowsHitTesting(showsPages)
                        .accessibilityHidden(!showsPages)
                        .background(pageBackground)
                        // The sheet's own background where it's opaque.
                        .tabPageBackground()
                        .environment(\.isHomeSheetTab, tab != .home)
                        .environment(\.isHomeSheetCollapsed, !showsPages)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(tab)
                }
            }
        } else {
            homeList
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: HomeTab) -> some View {
        switch tab {
        case .home:
            // Removed on the collapsed sheet, not just hidden as the other tabs
            // are: rows built while hidden stayed out of the accessibility tree
            // after the sheet rose, leaving VoiceOver the section's cells with
            // nothing in them. Kept while a stacked sheet covers it, though,
            // which collapses the sheet (`SheetCoordinator.baseDetentBeforeStacking`):
            // its rows were built while visible, and closing a stop should find
            // the list where the rider left it.
            if showsPages || !coordinator.stackedRoutes.isEmpty {
                homeList
            } else {
                Color.clear
            }
        case .recent:
            RecentStopsSheetView(application: application)
        case .bookmarks:
            BookmarksSheetView(application: application)
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

    /// Home's content, under the search row and tab bar.
    ///
    /// Always a list: Settings and More, last, shows whatever else does,
    /// since nothing else on the panel leads to the map's options or settings.
    private var homeList: some View {
        List {
            // Over Settings and More, when nothing else shows. Not before the
            // first settle: until nearby has had its chance, "empty" isn't a fact.
            if viewModel.showsEmptyState {
                emptyState
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(viewModel.visibleSections, id: \.self) { section in
                sectionContent(for: section)
            }
            settingsSection
        }
        // Applied to the `List`, matching `BookmarksListView`, rather than
        // to the bookmarks `Section` alone.
        .environment(\.obaFormatters, application.formatters)
        .searchListChrome()
    }

    // MARK: - Search Bar

    private var searchField: some View {
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
        .accessibilityIdentifier("home_search_button")
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
        case .bookmarks:
            bookmarksSection
        case .nearby:
            nearbySection
        case .recent:
            recentSection
        case .explore:
            exploreSection
        }
    }

    /// What leaves from the stops nearest the map's center; see
    /// `HomeNearbyDepartures`. A stop with nothing to list shows as a stop.
    private var nearbySection: some View {
        Section {
            ForEach(viewModel.nearbyDepartures.rows) { row in
                switch row {
                case .departure(let departure):
                    HomeNearbyDepartureRow(departure: departure, userLocation: viewModel.currentLocation) {
                        coordinator.push(.stopDetails(stopID: departure.stop.id))
                    }
                case .stop(let stop):
                    HomeStopRow(stop: stop) {
                        coordinator.push(.stopDetails(stopID: stop.id))
                    }
                }
            }
        } header: {
            HomeSectionHeader(title: Strings.nearbyStops) {
                showAll(.nearbyAll)
            }
        }
        .textCase(nil)
    }

    /// The last few stops viewed. Alarms, which the Recent tab also lists, have
    /// their shortcut in Explore.
    private var recentSection: some View {
        Section {
            ForEach(viewModel.recent.stops.prefix(HomeSheetSection.recentPreviewLimit), id: \.id) { stop in
                HomeStopRow(stop: stop) {
                    coordinator.push(.stopDetails(stopID: stop.id))
                }
            }
        } header: {
            HomeSectionHeader(title: Strings.recentStops) {
                showAll(.recentStopsAll)
            }
        }
        .textCase(nil)
    }

    private var exploreSection: some View {
        Section {
            HomeExploreRow(items: viewModel.exploreItems, onSelect: open(_:))
                .padding(.vertical, 4)
        } header: {
            HomeSectionTitle(title: Strings.explore)
        }
        .textCase(nil)
    }

    private func open(_ item: HomeExploreItem) {
        switch item {
        case .planTrip:
            coordinator.push(.tripPlanner(TripPlannerRequest()))
        case .rentals(let isOn):
            viewModel.toggleRentals()
            // Switched on behind a sheet that covers the map, the layer would
            // change nothing the rider can see.
            if !isOn, coordinator.currentDetent == AppSheetRoute.largeDetent {
                coordinator.currentDetent = .medium
            }
        case .alarms:
            showAll(.recentStopsAll)
        }
    }

    /// The map's options, settings and More. More only where the sheet has
    /// tabs; regular width keeps its More button on the map.
    private var settingsSection: some View {
        Section {
            ForEach(HomeSettingsItem.items(offersMore: showsTabs)) { item in
                HomeSettingsRow(
                    item: item,
                    offersDonations: offersDonations ?? application.donationsManager.donationsEnabled
                ) { open(item) }
            }
        } header: {
            HomeSectionTitle(title: Strings.settingsAndMore)
        }
        .textCase(nil)
    }

    private func open(_ item: HomeSettingsItem) {
        switch item {
        case .customizeMap:
            pushUnlessOnTop(.mapSettings)
        case .settings:
            onOpenSettings()
        case .more:
            pushUnlessOnTop(.more)
        }
    }

    /// A second tap before the stacked sheet covers the row would stack an
    /// identical copy on the first.
    private func pushUnlessOnTop(_ route: AppSheetRoute) {
        guard coordinator.stackedRoutes.last != route else { return }
        coordinator.push(route)
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
            HomeSectionTitle(title: Strings.serviceAlerts)
        }
        .textCase(nil)
    }

    /// The bookmarks as cards in a row that scrolls sideways, edge to edge: the
    /// row has no card of its own, each bookmark does.
    private var bookmarksSection: some View {
        Section {
            HomeBookmarkCards(
                rows: viewModel.bookmarks.rows,
                onSelect: { coordinator.push(.stopDetails(stopID: $0.stopID)) },
                onTogglePin: { viewModel.bookmarks.togglePin($0.bookmark) }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            HomeSectionHeader(title: Strings.bookmarks) {
                showAll(.bookmarksAll)
            }
        }
        .textCase(nil)
    }

    /// Shown only when every section is empty at once — a first launch, or
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
