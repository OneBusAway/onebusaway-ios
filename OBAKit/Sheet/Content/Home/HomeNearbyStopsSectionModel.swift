//
//  HomeNearbyStopsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import OBAKitCore

/// The home sheet's nearby-stops preview: the few stops closest to the map's
/// center.
///
/// Reads `MapStopsObserver` rather than subscribing to `MapRegionManager`
/// itself. The observer is already that manager's subscriber, and a second
/// delegate would redo the accumulate-and-prune work on every map settle for
/// the sake of four rows. This costs no network requests at all — it re-slices
/// stops the map has already loaded.
@MainActor
final class HomeNearbyStopsSectionModel: ObservableObject {

    @Published private(set) var stops: [Stop] = []

    private let observer: MapStopsObserver
    private let limit: Int
    private var cancellables = Set<AnyCancellable>()

    init(observer: MapStopsObserver, limit: Int = HomeSheetSection.itemLimit) {
        self.observer = observer
        self.limit = limit

        observer.$stops
            .combineLatest(observer.$viewportCenter)
            .sink { [weak self] stops, center in
                self?.rebuild(stops: stops, center: center)
            }
            .store(in: &cancellables)
    }

    /// `combineLatest` emits on subscribe, so the initial state is set by the
    /// sink above rather than duplicated here.
    private func rebuild(stops: [Stop], center: CLLocationCoordinate2D?) {
        guard let center else {
            // No settle yet. The observer's id ordering is arbitrary but stable,
            // which beats rendering an empty section for the frame or two before
            // the first camera settle lands.
            self.stops = Array(stops.prefix(limit))
            return
        }
        self.stops = Stop.nearest(stops, to: center, limit: limit)
    }
}
