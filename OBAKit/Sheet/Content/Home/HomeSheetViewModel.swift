//
//  HomeSheetViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore

// MARK: - HomeSheetViewModel

/// Owns the home sheet's reactive content state: the search bar's placeholder
/// and the three preview sections.
///
/// Composes three child section models rather than talking to the data sources
/// itself, so each section's rules stay separately readable and testable.
@MainActor
final class HomeSheetViewModel: NSObject, ObservableObject, RegionsServiceDelegate {

    let alerts: HomeAlertsSectionModel
    let nearby: HomeNearbyStopsSectionModel
    /// What leaves from the stops `nearby` holds; see `HomeNearbyDepartures`.
    let nearbyDepartures: HomeNearbyDeparturesSectionModel
    let recent: HomeRecentStopsSectionModel
    let bookmarks: HomeBookmarksSectionModel

    /// Published rather than computed so a region change repaints the search bar.
    /// The UIKit panel gets this from its own `RegionsServiceDelegate` callback
    /// (`MapFloatingPanelController.regionsService(_:updatedRegion:)`); a plain
    /// computed property would leave the placeholder naming the old region until
    /// something unrelated happened to invalidate the view.
    @Published private(set) var searchPlaceholder: String

    /// Whether the trip planner is reachable from this region at all, which is
    /// what decides if the discovery tip pointing at the search bar has anything
    /// to introduce. Same gate the placeholder copy uses, published for the same
    /// reason — a region change has to repaint it.
    @Published private(set) var offersTripPlanning: Bool

    /// Sections that currently have something to show, in render order. Empty
    /// sections are dropped entirely — header included.
    @Published private(set) var visibleSections: [HomeSheetSection] = []

    /// The Explore row's shortcuts; see `HomeExploreItem`.
    @Published private(set) var exploreItems: [HomeExploreItem] = []

    /// Whether Explore holds More, which it does where the sheet has tabs; set
    /// by the sheet, which knows. See `HomeExploreItem.more`.
    var offersMore = false {
        didSet {
            guard offersMore != oldValue else { return }
            updateExploreItems()
        }
    }

    /// Whether the sheet knows enough to say its sections are genuinely
    /// empty. False until the map's first camera settle.
    ///
    /// Recents and bookmarks are read from the store synchronously in the
    /// section models' initializers, so they're already accurate at first body
    /// evaluation. Nearby isn't: it's empty until the map settles. Without this
    /// gate, a cold open with nothing saved paints "Nothing Here Yet" for a frame
    /// or two before the nearby stops arrive and replace it.
    @Published private(set) var hasLoadedInitialContent = false

    private let application: Application
    private var cancellables = Set<AnyCancellable>()

    init(application: Application, stopsObserver: MapStopsObserver) {
        self.application = application
        self.searchPlaceholder = SearchPlaceholder.text(for: application)
        self.offersTripPlanning = application.features.tripPlanning == .running
        self.alerts = HomeAlertsSectionModel(alertsStore: application.alertsStore)
        self.nearby = HomeNearbyStopsSectionModel(observer: stopsObserver)
        self.recent = HomeRecentStopsSectionModel(application: application)
        let bookmarks = HomeBookmarksSectionModel(application: application)
        self.bookmarks = bookmarks
        self.nearbyDepartures = HomeNearbyDeparturesSectionModel(application: application) { [weak bookmarks] in
            Set((bookmarks?.selection ?? []).compactMap(TripBookmarkKey.init(bookmark:)))
        }
        super.init()

        // `RegionsService` holds delegates weakly, so there's nothing to unregister.
        application.regionsService.addDelegate(self)

        // Republish the children's changes as our own.
        //
        // `HomeSheetView` is handed this object and reads section content through
        // it (`viewModel.recent.stops`). SwiftUI subscribes to the object a view
        // is given and never to nested `ObservableObject`s reached through it, so
        // without this a child's `@Published` write updates the model and leaves
        // the sheet rendering stale rows. `visibleSections` below can't stand in
        // for it: it's guarded against no-op writes, so a stop viewed while the
        // Recent section is already on screen would publish nothing at all.
        //
        // Forwarding `objectWillChange` rather than the specific publishers used
        // below so a `@Published` added to a section model later is covered
        // automatically. Delivery is synchronous on the child's `willSet`, which
        // is the timing SwiftUI wants.
        Publishers.MergeMany(
            alerts.objectWillChange,
            nearby.objectWillChange,
            nearbyDepartures.objectWillChange,
            recent.objectWillChange,
            bookmarks.objectWillChange
        )
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)

        // Latched in the observer, so this fires at most once with `true` — and
        // fires immediately with `true` when the sheet is rebuilt against an
        // observer that has already settled.
        stopsObserver.$hasSettledOnce
            .sink { [weak self] hasSettled in
                guard let self, hasSettled, !self.hasLoadedInitialContent else { return }
                self.hasLoadedInitialContent = true
            }
            .store(in: &cancellables)

        // The departures model works from the same stops the nearby model picks.
        nearby.$stops
            .sink { [weak self] stops in self?.nearbyDepartures.stops = stops }
            .store(in: &cancellables)

        // A bookmark added or removed changes which departures Nearby leaves to
        // the cards above it.
        bookmarks.$rows
            .map { $0.map(\.id) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.nearbyDepartures.rebuildRows() }
            .store(in: &cancellables)

        // The map's layers come and go with the region, and are switched from
        // the Map sheet as well as from Explore.
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .mapLayerAvailabilityDidChange),
            NotificationCenter.default.publisher(for: .mapLayerEnabledStateDidChange)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateExploreItems() }
        .store(in: &cancellables)

        // Recompute the visible set whenever any child's content changes. The
        // children publish values, not the section list, so this is the single
        // place the order and the omission rule live.
        nearby.$stops
            .combineLatest(recent.$stops, bookmarks.$rows)
            .combineLatest(alerts.$alerts, $exploreItems)
            .sink { [weak self] content, alerts, exploreItems in
                let (nearbyStops, recentStops, bookmarkRows) = content
                self?.updateVisibleSections(
                    hasAlerts: !alerts.isEmpty,
                    hasBookmarks: !bookmarkRows.isEmpty,
                    hasNearby: !nearbyStops.isEmpty,
                    hasRecent: !recentStops.isEmpty,
                    explore: exploreItems
                )
            }
            .store(in: &cancellables)

        recent.$alarmCount
            .removeDuplicates()
            .sink { [weak self] count in self?.updateExploreItems(alarmCount: count) }
            .store(in: &cancellables)
    }

    /// Called when the sheet's content appears. Idempotent: the sheet system
    /// tears content down and rebuilds it without the user navigating anywhere,
    /// so this can fire several times per visit. Every step here is a no-op when
    /// nothing changed: the store reads are cheap and their results are only
    /// published when they differ, and the bookmark fetch is gated on staleness,
    /// region, and selection.
    func activate() {
        // The store's high-severity list is windowed on the clock (eight hours),
        // so an alert can age out between the store's own fetches.
        alerts.reload()
        recent.reload()
        bookmarks.loadIfNeeded()
        // A countdown moves without a fetch, so the rows are rebuilt each poll.
        nearbyDepartures.loadIfNeeded()
        nearbyDepartures.rebuildRows()
    }

    /// Explore's shortcuts to features don't make the sheet non-empty: alone,
    /// they would replace "Nothing Here Yet" with a row of buttons on a first
    /// launch. So Explore shows beside another section, when it has something
    /// of the rider's own, their alarms, or when it holds More, which has to be
    /// reachable always; the sheet then draws the empty state over it
    /// (`showsEmptyState`).
    private func updateVisibleSections(
        hasAlerts: Bool,
        hasBookmarks: Bool,
        hasNearby: Bool,
        hasRecent: Bool,
        explore: [HomeExploreItem]
    ) {
        var sections: [HomeSheetSection] = []
        if hasAlerts { sections.append(.alerts) }
        if hasBookmarks { sections.append(.bookmarks) }
        if hasNearby { sections.append(.nearby) }
        if hasRecent { sections.append(.recent) }
        let hasAlarms = explore.contains { if case .alarms = $0 { true } else { false } }
        if !explore.isEmpty, hasAlarms || explore.contains(.more) || !sections.isEmpty { sections.append(.explore) }
        guard sections != visibleSections else { return }
        visibleSections = sections
    }

    /// Whether the sheet says "Nothing Here Yet": no section but Explore, and
    /// not before the first settle (see `hasLoadedInitialContent`). Alarms
    /// are the rider's own, so Explore holding them isn't empty.
    var showsEmptyState: Bool {
        guard hasLoadedInitialContent, visibleSections.allSatisfy({ $0 == .explore }) else { return false }
        return !exploreItems.contains { if case .alarms = $0 { true } else { false } }
    }

    // MARK: - Explore

    /// The map's bike and scooter layers that this region can show.
    private var rentalLayers: [MapLayer] {
        application.mapRegionManager.mapLayers.filter { $0.group == .otherModes && $0.availability != .unsupported }
    }

    /// Whether the bike and scooter layers are on, or `nil` in a region with
    /// none. On when any is: the tile then switches them all off.
    private var rentalsEnabled: Bool? {
        let layers = rentalLayers
        guard !layers.isEmpty else { return nil }
        return layers.contains { application.mapRegionManager.isMapLayerEnabled(id: $0.id) }
    }

    /// - Parameter alarmCount: The count being published, when called from its
    ///   own `willSet`, where the model still holds the old one.
    private func updateExploreItems(alarmCount: Int? = nil) {
        let items = HomeExploreItem.items(
            offersTripPlanning: offersTripPlanning,
            rentalsEnabled: rentalsEnabled,
            alarmCount: alarmCount ?? recent.alarmCount,
            offersMore: offersMore
        )
        guard items != exploreItems else { return }
        exploreItems = items
    }

    /// Shows the map's bikes and scooters, or hides them if any are showing.
    /// The layers post their change, which is what redraws the tile.
    func toggleRentals() {
        let turnOn = rentalsEnabled == false
        for layer in rentalLayers {
            application.mapRegionManager.setMapLayerEnabled(turnOn, id: layer.id)
        }
        updateExploreItems()
    }

    /// Where the Nearby tab's list is centered: the map's, as the section's
    /// stops are.
    var nearbyCoordinate: CLLocationCoordinate2D? {
        NearbyCoordinateResolver.coordinate(
            viewportCenter: nearby.viewportCenter,
            currentLocation: application.locationService.currentLocation,
            region: application.currentRegion
        )
    }

    /// The rider's location, for the Nearby rows' walk times.
    var currentLocation: CLLocation? {
        application.locationService.currentLocation
    }

    // MARK: - RegionsServiceDelegate

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        alerts.reload()
        searchPlaceholder = SearchPlaceholder.text(for: application)
        offersTripPlanning = application.features.tripPlanning == .running
        updateExploreItems()
        // Which recents and bookmarks are "current" changed, and neither store
        // posts a notification for it.
        recent.reload()
        bookmarks.loadIfNeeded()
    }
}
