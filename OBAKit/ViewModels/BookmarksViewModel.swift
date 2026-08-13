//
//  BookmarksViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import CoreLocation
import OBAKitCore

/// Screen model for the Bookmarks tab.
///
/// Owns the `BookmarkDataLoader`, builds the displayable section list
/// (`sections`), and tracks collapse state and highlight-on-change flags.
/// Observed by `BookmarksListView` (SwiftUI) and by the hosting
/// `BookmarksViewController` (Combine `sink`s for chrome and Live Activities).
/// Contains no UIKit imports.
///
/// Subclasses NSObject to adopt the `BookmarkDataDelegate` protocol.
@MainActor
class BookmarksViewModel: NSObject, ObservableObject, BookmarkDataDelegate {

    // MARK: - Published State

    /// Fires each time arrival data is refreshed, after `sections` has been
    /// rebuilt. The hosting controller listens to push updates into any
    /// running Live Activities.
    var didUpdate: AnyPublisher<Void, Never> {
        didUpdateSubject.eraseToAnyPublisher()
    }
    private let didUpdateSubject = PassthroughSubject<Void, Never>()

    /// The displayable section list, rebuilt by `rebuildSections()` whenever
    /// bookmarks, arrival data, sort preference, or the region change.
    @Published private(set) var sections: [BookmarkListSection] = []

    /// IDs of sections the user has collapsed. Persisted under the same
    /// UserDefaults key (and encoding) the legacy `BookmarksViewController`
    /// used, so existing users' collapse state survives the rewrite.
    @Published private(set) var collapsedSectionIDs: Set<String>

    /// Empty-state content, consulted by the view only when `sections` is
    /// empty — which is why there's no bookmark-count check here: bookmarks
    /// that exist only in *other* regions still deserve the empty state, not a
    /// blank list. The migration variant takes priority so users of the old
    /// app generation know where their bookmarks went.
    var emptyState: (title: String, body: String) {
        if application.hasDataToMigrate {
            return (Strings.emptyBookmarkTitle, Strings.emptyBookmarkBodyWithPendingMigration)
        }
        return (Strings.emptyBookmarkTitle, Strings.emptyBookmarkBody)
    }

    /// `true` while the data loader has any per-bookmark fetch in flight.
    /// Drives spinner UI in consumers; transitions are reported by the loader
    /// once per batch boundary (not once per individual fetch).
    @Published private(set) var isLoading: Bool = false

    /// `true` when the user has chosen to sort bookmarks by group (vs. by distance).
    @Published var sortByGroup: Bool

    /// Whether the most-recently-completed refresh batch had any failed fetch.
    /// Read by the VC when `isLoading` transitions to `false` to pick success vs.
    /// failure haptic feedback. Not `@Published` — it's a direct read, not an observed sink.
    private(set) var lastRefreshHadError: Bool = false

    // MARK: - Private

    private let application: Application
    private var dataLoader: BookmarkDataLoader!

    private enum UserDefaultsKey: String {
        case sortByGroup = "OBABookmarksController_SortBookmarksByGroup"
        /// Same key (and `Set<String>` JSON encoding) as the legacy controller's
        /// `collapsedSections` property — do not rename.
        case collapsedSections = "collapsedBookmarkSections"
    }

    // MARK: - Init

    init(application: Application) {
        self.application = application
        application.userDefaults.register(defaults: [UserDefaultsKey.sortByGroup.rawValue: true])
        self.sortByGroup = application.userDefaults.bool(forKey: UserDefaultsKey.sortByGroup.rawValue)
        let decodedCollapsedSections = (try? application.userDefaults.decodeUserDefaultsObjects(
            type: Set<String>.self,
            key: UserDefaultsKey.collapsedSections.rawValue)) ?? nil
        self.collapsedSectionIDs = decodedCollapsedSections ?? []
        super.init()
        self.dataLoader = BookmarkDataLoader(application: application, delegate: self)
        // Distance sorting needs the user's location, which often arrives after
        // `start()` — especially on cold launch. Stop-only bookmark sets never
        // fire `dataLoaderDidUpdate`, so without this the group-sort fallback
        // would persist until the next manual refresh.
        application.locationService.addDelegate(self)
    }

    isolated deinit {
        application.locationService.removeDelegate(self)
        dataLoader?.cancelUpdates()
    }

    // MARK: - Lifecycle

    /// Call from `viewWillAppear` / `.task`. Rebuilds the section list
    /// immediately (arrival data arrives asynchronously, and stop-only
    /// bookmark sets produce no `didUpdate` at all) and starts the
    /// 30-second refresh cycle.
    func start() {
        rebuildSections()
        dataLoader.loadData()
    }

    /// Call from `viewWillDisappear` / `.onDisappear`.
    func deactivate() {
        dataLoader.cancelUpdates()
    }

    // MARK: - Refresh

    func refresh() {
        dataLoader.loadData()
    }

    /// Drives `.refreshable`: kicks off a refresh batch and suspends until
    /// *that batch* drains (or is retired by `deactivate()`). The loader scopes
    /// the await to the batch this call started, so a previously in-flight
    /// auto-refresh batch completing first can't end the pull early.
    func refreshAndWait() async {
        await dataLoader.loadDataAndWait()
    }

    // MARK: - Sort

    func updateSortType(byGroup: Bool) {
        sortByGroup = byGroup
        application.userDefaults.setValue(byGroup, forKey: UserDefaultsKey.sortByGroup.rawValue)
        rebuildSections()
    }

    // MARK: - Section Collapse

    func toggleSectionCollapsed(_ sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }

        do {
            try application.userDefaults.encodeUserDefaultsObjects(collapsedSectionIDs, key: UserDefaultsKey.collapsedSections.rawValue)
        } catch let error {
            Logger.error("Unable to encode collapsedSectionIDs: \(error)")
        }
    }

    // MARK: - Data Access

    /// Returns arrival/departure data for the given bookmark's trip key.
    func arrivalDepartures(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return dataLoader.dataForKey(key)
    }

    // MARK: - Bookmark Management

    func deleteBookmark(_ bookmark: Bookmark) {
        application.userDataStore.delete(bookmark: bookmark)
        rebuildSections()
    }

    // MARK: - Section Building

    /// Rebuilds `sections` from the data store and the loader's current
    /// arrival data. Also the only place `shouldHighlight(arrivalDeparture:)`
    /// may run — it mutates the last-seen-minutes table, so calling it from a
    /// view body or computed property would corrupt highlight tracking.
    func rebuildSections() {
        // sectionsSortedByDistance() falls back to group sorting when no
        // location is available.
        let newSections = sortByGroup ? sectionsSortedByGroup() : sectionsSortedByDistance()

        // The loader reports once per bookmark fetch; skip the publish (and
        // the SwiftUI diff it triggers) when nothing visible changed.
        if newSections != sections {
            sections = newSections
        }
    }

    private func sectionsSortedByGroup() -> [BookmarkListSection] {
        var sections = application.userDataStore.bookmarkGroups.compactMap { buildSection(group: $0) }

        // Add ungrouped bookmarks
        if let ungrouped = buildSection(group: nil) {
            sections.append(ungrouped)
        }

        return sections
    }

    private func buildSection(group: BookmarkGroup?) -> BookmarkListSection? {
        buildSection(
            bookmarks: application.userDataStore.bookmarksInGroup(group),
            id: group?.id.uuidString ?? "unknown_group",
            title: group?.name ?? OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title", value: "Bookmarks", comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group.")
        )
    }

    /// Builds a single section containing all bookmarks in the current region,
    /// sorted by distance from the user's current location.
    private func sectionsSortedByDistance() -> [BookmarkListSection] {
        guard let currentLocation = application.locationService.currentLocation else {
            return sectionsSortedByGroup()
        }

        // Compute each distance once rather than inside the sort comparator.
        let bookmarks = application.userDataStore.bookmarks
            .map { ($0, $0.stop.location.distance(from: currentLocation)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        return [buildSection(
            bookmarks: bookmarks,
            id: "distance_sorted_group",
            title: OBALoc("bookmarks_controller.sorted_by_distance_header", value: "Sorted by Distance", comment: "The table section header on the bookmarks controller for when bookmarks are sorted by distance.")
        )].compactMap { $0 }
    }

    private func buildSection(bookmarks: [Bookmark], id: String, title: String) -> BookmarkListSection? {
        let currentRegionID = application.regionsService.currentRegion?.id
        let activeBookmarks = bookmarks.filter { $0.regionIdentifier == currentRegionID }

        guard !activeBookmarks.isEmpty else { return nil }

        return BookmarkListSection(id: id, title: title, rows: activeBookmarks.map { buildRow($0) })
    }

    private func buildRow(_ bookmark: Bookmark) -> BookmarkRowViewModel {
        var arrDeps: [ArrivalDeparture] = []
        var highlighted = Set<TripIdentifier>()

        if bookmark.isTripBookmark {
            arrDeps = arrivalDepartures(for: bookmark)
            for arrDep in arrDeps where shouldHighlight(arrivalDeparture: arrDep) {
                highlighted.insert(arrDep.tripID)
            }
        }

        return BookmarkRowViewModel(
            bookmark: bookmark,
            arrivalDepartures: arrDeps,
            highlightedTripIDs: highlighted,
            hasLoadedArrivalData: dataLoader.hasFetchedData(forStopID: bookmark.stopID)
        )
    }

    // MARK: - Arrival departure highlight updates

    private var arrivalDepartureTimes = ArrivalDepartureTimes()

    /// Used to determine if a departure's badge should 'flash' when next rendered,
    /// indicating the departure time for the `ArrivalDeparture` object has changed.
    ///
    /// Stateful: records the latest minutes for future comparison, so it must run
    /// exactly once per departure per `rebuildSections()` pass.
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object
    /// - Returns: Whether or not to highlight the ArrivalDeparture in its row.
    private func shouldHighlight(arrivalDeparture: ArrivalDeparture) -> Bool {
        var highlight = false
        if let lastMinutes = arrivalDepartureTimes[arrivalDeparture.tripID] {
            highlight = lastMinutes != arrivalDeparture.arrivalDepartureMinutes
        }

        arrivalDepartureTimes[arrivalDeparture.tripID] = arrivalDeparture.arrivalDepartureMinutes

        return highlight
    }

    // MARK: - BookmarkDataDelegate

    nonisolated func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        // BookmarkDataLoader dispatches this callback inside `await MainActor.run`, so
        // we're already on the main actor. `assumeIsolated` confirms that without the
        // round-trip Task hop. Traps loudly if the loader's contract ever changes.
        MainActor.assumeIsolated {
            rebuildSections()
            didUpdateSubject.send()
        }
    }

    nonisolated func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool) {
        MainActor.assumeIsolated {
            // Capture the batch's error state before flipping `isLoading`, so the VC's
            // `$isLoading` sink reads an up-to-date `lastRefreshHadError` when it fires.
            if !isLoading {
                self.lastRefreshHadError = dataLoader.lastBatchHadError
            }
            self.isLoading = isLoading
        }
    }
}

// MARK: - LocationServiceDelegate

extension BookmarksViewModel: LocationServiceDelegate {
    /// Re-sorts when the user's location arrives or changes; the rebuild is
    /// equality-gated, so group-sorted users pay nothing for this.
    nonisolated func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        // CLLocationManager delivers delegate callbacks on the thread its
        // manager was created on — the main thread here (see LocationService).
        MainActor.assumeIsolated {
            rebuildSections()
        }
    }
}
