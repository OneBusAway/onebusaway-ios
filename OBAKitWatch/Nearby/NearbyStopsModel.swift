//
//  NearbyStopsModel.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Observation
import OBAKitCore

/// Drives the Nearby screen: one location fix → region check → stops.
///
/// All branching that can be tested lives in OBAKitCore (`NearbyStopsLoader`,
/// `LocationService.requestLocation`, `RegionsService`); this maps their
/// results to a `Phase`.
@MainActor
@Observable
public final class NearbyStopsModel {
    public enum Phase: Equatable {
        case awaitingAuthorization
        case locationDenied
        case locating
        case noRegion
        case failed(String)
        case empty
        case loaded([Stop])
    }

    public private(set) var phase: Phase
    /// The fix the current list was fetched around; rows show distance from it.
    public private(set) var origin: CLLocation?
    /// The region containing the last fix; the screen title.
    public private(set) var regionName: String?

    @ObservationIgnored private let host: WatchAppHost?
    @ObservationIgnored private let loader = NearbyStopsLoader()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(host: WatchAppHost) {
        self.host = host
        self.phase = .locating
    }

    /// For previews and tests: a fixed phase, no services.
    public init(phase: Phase, origin: CLLocation? = nil, regionName: String? = nil) {
        self.host = nil
        self.phase = phase
        self.origin = origin
        self.regionName = regionName
    }

    /// Re-requests location and reloads. A refresh already in flight is
    /// cancelled; the one-shot it was awaiting still resolves and is ignored.
    public func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await performRefresh() }
    }

    private func performRefresh() async {
        guard let host, isAuthorized(host) else { return }

        phase = .locating

        let fix: CLLocation
        do {
            fix = try await host.locationService.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
            return
        }
        guard !Task.isCancelled else { return }
        origin = fix

        // `currentRegion` keeps the previous launch's region when a fix lands
        // outside every region, so the rule keys off where the watch *is*.
        guard let region = host.regionsService.physicallyLocatedRegion else {
            regionName = nil
            phase = .noRegion
            return
        }
        regionName = region.name

        // The fix above set currentLocation → RegionsService selected the
        // region → StandaloneAPIServiceProvider rebuilt the service → the host
        // republished it, all synchronously on the main actor.
        guard let apiService = host.apiService else {
            phase = .noRegion
            return
        }

        await loadStops(near: fix, using: apiService)
    }

    /// Sets the phase for a status that cannot produce a fix, requesting
    /// authorization when it has not been asked for yet.
    private func isAuthorized(_ host: WatchAppHost) -> Bool {
        switch host.locationService.authorizationStatus {
        case .notDetermined:
            phase = .awaitingAuthorization
            host.locationService.requestInUseAuthorization()
            return false
        case .denied, .restricted:
            phase = .locationDenied
            return false
        default:
            return true
        }
    }

    private func loadStops(near fix: CLLocation, using apiService: RESTAPIService) async {
        do {
            let stops = try await loader.stops(near: fix.coordinate, using: apiService)
            guard !Task.isCancelled else { return }
            phase = stops.isEmpty ? .empty : .loaded(stops)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
