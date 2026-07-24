//
//  MapStopsObserver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// Bridges `MapRegionManager`'s `stopsUpdated` callback to `@Published` arrays
/// a SwiftUI `Map` can render (stops + bookmarks).
///
/// The rendered set **accumulates** across settles (like the UIKit map, until
/// zoom-out) so panning back is instant, bounded by a distance band around the
/// last viewport plus a count cap. Deliberately separate from
/// `mapRegionManager.stops`, which holds only the latest region.
@MainActor
final class MapStopsObserver: NSObject, ObservableObject, MapRegionDelegate {

    /// A stop with its precomputed label, so the `Map` builder needn't filter or
    /// format per body eval.
    struct RenderStop: Identifiable {
        let stop: Stop
        let title: String
        var id: StopID { stop.id }
    }

    /// The accumulated, pruned, id-sorted render set the `Map` draws.
    @Published private(set) var stops: [Stop] = [] {
        didSet { rebuildRenderStops() }
    }

    /// Non-bookmarked, labeled stops, rebuilt only on stop/bookmark changes.
    @Published private(set) var renderStops: [RenderStop] = []

    /// Bookmarks for the current region, deduped by stop (last wins). Decoded
    /// once here rather than per-pin in the annotation builder.
    @Published private(set) var bookmarks: [Bookmark] = []

    /// IDs of bookmarked stops, so regular stop pins can exclude them.
    private(set) var bookmarkedStopIDs: Set<StopID> = []

    /// Evict pins beyond this multiple of the viewport span.
    private let pruneSpanFactor: Double

    /// Hard cap on rendered pins (frame-rate backstop for dense metros).
    private let renderCap: Int

    /// Accumulated stops keyed by ID — the render set before publishing.
    private var accumulated: [StopID: Stop] = [:]

    /// Last settled viewport, the prune reference. Nil = no prune (set grows).
    private var viewport: MKCoordinateRegion?

    private let application: Application

    init(application: Application, pruneSpanFactor: Double = 4.0, renderCap: Int = 400) {
        self.application = application
        self.pruneSpanFactor = pruneSpanFactor
        self.renderCap = renderCap
        super.init()

        // Seed the accumulator (and published set) so a re-created observer
        // isn't empty.
        for stop in application.mapRegionManager.stops {
            accumulated[stop.id] = stop
        }
        stops = orderedStops()
        application.mapRegionManager.addDelegate(self)

        reloadBookmarks()
        // Re-decode on bookmark changes so a visible pin restyles. Selector-based
        // observation is auto-removed on dealloc, so no token/deinit needed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarksDidChange),
            name: .bookmarksDidChange,
            object: nil
        )
    }

    /// Clears the render set and prune reference on zoom-out. Bookmarks stay
    /// (like the UIKit map, at every zoom level).
    func reset() {
        accumulated.removeAll()
        viewport = nil
        guard !stops.isEmpty else { return }
        stops = []
    }

    /// Records the settled viewport and prunes against it. Pruning here (not
    /// only in `stopsUpdated`) bounds the set even on settles that load no
    /// stops. Loop-safe: a re-fired same-region settle changes nothing.
    func updateViewport(_ region: MKCoordinateRegion) {
        viewport = region
        if pruneAccumulated() {
            publish()
        }
    }

    // MARK: - Bookmarks

    /// `.bookmarksDidChange` may be posted off the main actor, so hop rather
    /// than assume isolation.
    @objc
    private nonisolated func bookmarksDidChange() {
        Task { @MainActor [weak self] in
            self?.reloadBookmarks()
        }
    }

    private func reloadBookmarks() {
        let regionBookmarks = application.userDataStore.findBookmarks(in: application.currentRegion)
        let bookmarksByStopID = regionBookmarks.dedupedByStopID()

        bookmarkedStopIDs = Set(bookmarksByStopID.keys)
        // Keep the store's ordering (deduped to each stop's winning bookmark)
        // so republished arrays are deterministic across reloads.
        bookmarks = regionBookmarks.filter { bookmarksByStopID[$0.stopID] === $0 }
        rebuildRenderStops()
    }

    // MARK: - MapRegionDelegate

    // `@objc` so Obj-C runtime discovery of this optional-protocol method is explicit.
    @objc
    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        // Add new stops and replace changed ones, but keep the instance for
        // unchanged stops so `ForEach` leaves those pins untouched.
        var mutated = false
        for stop in stops {
            if let existing = accumulated[stop.id], existing.isEqual(stop) {
                continue
            }
            accumulated[stop.id] = stop
            mutated = true
        }
        if pruneAccumulated() {
            mutated = true
        }
        if mutated {
            publish()
        }
    }

    // MARK: - Prune / publish

    /// Evicts stops outside the viewport band / beyond the cap. Returns `true`
    /// if anything was removed. Early-returns cheaply when nothing is out of
    /// bounds, so a no-op re-serve doesn't rebuild the dictionary.
    @discardableResult
    private func pruneAccumulated() -> Bool {
        guard let viewport else { return false }

        // Per-axis bounding box: `pruneSpanFactor` × the viewport half-span.
        let latLimit = viewport.span.latitudeDelta / 2 * pruneSpanFactor
        let lonLimit = viewport.span.longitudeDelta / 2 * pruneSpanFactor
        let center = viewport.center

        func isInBand(_ stop: Stop) -> Bool {
            abs(stop.coordinate.latitude - center.latitude) <= latLimit &&
                abs(stop.coordinate.longitude - center.longitude) <= lonLimit
        }

        let hasOutOfBand = accumulated.contains { !isInBand($0.value) }
        guard hasOutOfBand || accumulated.count > renderCap else { return false }

        if hasOutOfBand {
            accumulated = accumulated.filter { isInBand($0.value) }
        }

        // Count cap: keep the `renderCap` nearest to center, evict the rest.
        if accumulated.count > renderCap {
            let nearest = accumulated.values
                .sorted { squaredDistance($0, to: center) < squaredDistance($1, to: center) }
                .prefix(renderCap)
            accumulated = Dictionary(nearest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        return true
    }

    /// Squared distance with longitude scaled by `cos(latitude)` so lat/lon
    /// degrees compare on a common metric scale. Ordering only — no sqrt.
    private func squaredDistance(_ stop: Stop, to center: CLLocationCoordinate2D) -> Double {
        let dLat = stop.coordinate.latitude - center.latitude
        let dLon = (stop.coordinate.longitude - center.longitude) * cos(center.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    private func orderedStops() -> [Stop] {
        accumulated.values.sorted { $0.id < $1.id }
    }

    /// Rebuilds `renderStops` so the filter and title formatting run once per
    /// change, not per body eval.
    private func rebuildRenderStops() {
        renderStops = stops
            .filter { !bookmarkedStopIDs.contains($0.id) }
            .map { RenderStop(stop: $0, title: Formatters.formattedTitle(stop: $0)) }
    }

    /// Republishes the render set. Only called after a real mutation, so a
    /// re-fired settle never republishes (avoids the body-eval loop).
    private func publish() {
        stops = orderedStops()
    }
}
