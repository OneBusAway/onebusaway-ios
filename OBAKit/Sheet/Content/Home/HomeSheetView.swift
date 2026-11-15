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

/// The panel's base sheet: the search field, with More beside it, over a row of
/// filter chips that are its tabs on iPhone. For You, the first, is the mixed
/// view: bookmark cards, what leaves from nearby stops, recent stops and a row
/// of shortcuts. See `HomeTab`.
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
    /// Whether the tabs' pages show under the chips; see `HomeTabs.showsTabPages`.
    /// Kept as the Bool rather than the measured height, so a drag, which changes
    /// the height every frame, redraws this view only when it flips.
    @State private var showsPages = true
    /// Where the Nearby tab's list is centered. Moved when the tab is picked
    /// and the map has gone far enough to change what's near, which rebuilds the
    /// list there; otherwise the tab keeps its scroll position and search text
    /// as the others do.
    @State private var nearbyAnchor: CLLocationCoordinate2D?
    @ScaledMetric(relativeTo: .body) private var scaledMoreButtonSize: CGFloat = 50
    /// See `moreButton`.
    private var moreButtonSize: CGFloat { min(scaledMoreButtonSize, 64) }
    /// The map reads the header's height from here; see `HomeSheetMetrics`.
    /// `nil` outside the map panel.
    @Environment(HomeSheetMetrics.self) private var metrics: HomeSheetMetrics?

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

    /// Whether For You's list is on screen, which is when its Nearby section
    /// may fetch arrivals: unlike the bookmarks' poll, nothing off screen needs
    /// them.
    private var isHomeListVisible: Bool {
        isPollingHome && showsPages
    }

    var body: some View {
        // The search row and chips over the tabs rather than in a
        // `safeAreaInset`: `TabView` lays its pages out beneath an inset.
        VStack(spacing: 0) {
            header
                // The header keeps its height on the collapsed sheet, which is
                // fitted to it; the pages take what's left, down to nothing.
                .layoutPriority(1)
            tabs
                .frame(minHeight: 0)
                // Reduced to the Bool in the transform, like the clearance below.
                .onGeometryChange(for: Bool.self) { [showsTabs] proxy in
                    HomeTabs.showsTabPages(showsTabs: showsTabs, pageHeight: proxy.size.height)
                } action: { showsPages = $0 }
                // The pages reach the sheet's bottom edge, and sheet content
                // can't read the safe area there; see `HomeTabs.bottomClearance`.
                .contentMargins(.bottom, bottomClearance, for: .scrollContent)
        }
            // From the top, and clipped: a page hidden on the collapsed sheet may
            // still be taller than the room it leaves.
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            // Reduced to the clearance in the transform, so a drag, which moves
            // the sheet every frame, redraws this view only when the clearance
            // changes.
            .onGeometryChange(for: CGFloat.self) { [screenBottom] proxy in
                HomeTabs.bottomClearance(sheetBottom: proxy.frame(in: .global).maxY, screen: screenBottom)
            } action: { bottomClearance = $0 }
            // On the whole sheet, not just the pages: the chips sit on it. A no-op
            // where the sheet's Liquid Glass is the background (iOS 26, light mode).
            .searchSheetBackground()
            .ignoresSafeArea(.container, edges: showsTabs ? [] : .bottom)
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

    /// The search row over the chips, measured for the collapsed detent, which
    /// is fitted to it.
    private var header: some View {
        VStack(spacing: 0) {
            searchBarRow
                .padding(.top, 16)
                .padding(.bottom, HomeTabs.searchRowBottomPadding)
            if showsTabs {
                HomeTabBar(selection: selectedTab, onSelect: select(_:))
            }
        }
        // Its own height, however short the sheet: a squeezed header would
        // shrink the detent measured from it, which would squeeze it further.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // The map's copy, and the detent's, which can't read the map's.
            metrics?.headerHeight = height
            HomeCollapsedDetent.measured.withLock { $0.headerHeight = height }
        }
        .background(pageBackground)
    }

    /// Behind the header and each tab's page where the sheet shows its glass.
    /// `TabView` gives a page an opaque background there that
    /// `tabPageBackground()` doesn't always clear, which left a seam under the
    /// chips: glass over them, white under. Painted, the two can't differ.
    private var pageBackground: Color {
        showsTabs && colorScheme.showsSheetGlass ? Color(.systemBackground) : .clear
    }

    /// The tabs, in a `TabView` whose own bar is hidden for `HomeTabBar`. It
    /// builds each tab the first time it's picked and keeps it after, so leaving a
    /// tab and coming back keeps its scroll position and search text, and exposes
    /// only the visible tab to VoiceOver. Regular width has no tabs, so just For
    /// You.
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
            // nothing in them.
            if showsPages {
                homeList
            } else {
                Color.clear
            }
        case .bookmarks:
            BookmarksSheetView(application: application)
        case .nearby:
            NearbyStopsSheetView(application: application, coordinate: nearbyAnchor)
                .id(nearbyAnchor.map { "\($0.latitude),\($0.longitude)" })
        case .recent:
            RecentStopsSheetView(application: application)
        }
    }

    private func select(_ tab: HomeTab) {
        if tab == .nearby {
            nearbyAnchor = HomeTabs.nearbyAnchor(current: nearbyAnchor, mapCenter: viewModel.nearbyCoordinate)
        }
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

    /// For You's content, under the search row and chips.
    @ViewBuilder
    private var homeList: some View {
        if !viewModel.visibleSections.isEmpty {
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
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            // Pre-first-settle: nearby hasn't had its chance yet, so "empty"
            // isn't a fact. Hold the space rather than flash a wrong answer.
            Color.clear
        }
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        HStack(spacing: 8) {
            searchField
            // On iPhone, where the classic app's More tab went. Regular width
            // keeps its More button on the map.
            if showsTabs {
                moreButton
            }
        }
        .padding(.horizontal, 12)
    }

    /// As tall as the search field beside it, which is a line of body text and
    /// its padding, so it scales as that does: up to a point, past which it
    /// would take the width the placeholder needs.
    private var moreButton: some View {
        Button {
            coordinator.push(.more)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: moreButtonSize, height: moreButtonSize)
                .background { Circle().fill(Color(.tertiarySystemFill)) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.moreTabTitle)
        .accessibilityShowsLargeContentViewer {
            Label(Strings.moreTabTitle, systemImage: "ellipsis")
        }
    }

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
            // The header leads to the same list; this says so where the rows end,
            // which is where a rider who didn't find their stop is looking.
            Button {
                showAll(.nearbyAll)
            } label: {
                // Label-colored text with the brand's chevron, as the section
                // headers are: neither brand green passes 4.5:1 as text in both
                // appearances.
                HStack(spacing: 8) {
                    Text(Strings.allNearbyStops)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
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
