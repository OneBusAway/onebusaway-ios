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

    let nearby: HomeNearbyStopsSectionModel
    let recent: HomeRecentStopsSectionModel
    let bookmarks: HomeBookmarksSectionModel

    /// Published rather than computed so a region change repaints the search bar.
    /// The UIKit panel gets this from its own `RegionsServiceDelegate` callback
    /// (`MapFloatingPanelController.regionsService(_:updatedRegion:)`); a plain
    /// computed property would leave the placeholder naming the old region until
    /// something unrelated happened to invalidate the view.
    @Published private(set) var searchPlaceholder: String

    /// Sections that currently have something to show, in render order. Empty
    /// sections are dropped entirely — header included.
    @Published private(set) var visibleSections: [HomeSheetSection] = []

    /// Whether the sheet knows enough to say the three sections are genuinely
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
        self.nearby = HomeNearbyStopsSectionModel(observer: stopsObserver)
        self.recent = HomeRecentStopsSectionModel(application: application)
        self.bookmarks = HomeBookmarksSectionModel(application: application)
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
            nearby.objectWillChange,
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

        // Recompute the visible set whenever any child's content changes. The
        // children publish values, not the section list, so this is the single
        // place the order and the omission rule live.
        nearby.$stops
            .combineLatest(recent.$stops, bookmarks.$rows)
            .sink { [weak self] nearbyStops, recentStops, bookmarkRows in
                self?.updateVisibleSections(
                    hasNearby: !nearbyStops.isEmpty,
                    hasRecent: !recentStops.isEmpty,
                    hasBookmarks: !bookmarkRows.isEmpty
                )
            }
            .store(in: &cancellables)
    }

    /// Called when the sheet's content appears. Idempotent: the sheet system
    /// tears content down and rebuilds it without the user navigating anywhere,
    /// so this can fire several times per visit. Every step here is a no-op when
    /// nothing changed: the store reads are cheap and their results are only
    /// published when they differ, and the bookmark fetch is gated on staleness,
    /// region, and selection.
    func activate() {
        recent.reload()
        bookmarks.loadIfNeeded()
    }

    private func updateVisibleSections(hasNearby: Bool, hasRecent: Bool, hasBookmarks: Bool) {
        var sections: [HomeSheetSection] = []
        if hasNearby { sections.append(.nearby) }
        if hasRecent { sections.append(.recent) }
        if hasBookmarks { sections.append(.bookmarks) }
        guard sections != visibleSections else { return }
        visibleSections = sections
    }

    // MARK: - RegionsServiceDelegate

    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        searchPlaceholder = SearchPlaceholder.text(for: application)
        // Which recents and bookmarks are "current" changed, and neither store
        // posts a notification for it.
        recent.reload()
        bookmarks.loadIfNeeded()
    }
}
