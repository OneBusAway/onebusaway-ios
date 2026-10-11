//
//  RouteDirectionModel.swift
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

/// Drives the route screen: one route in one direction at its nearest few
/// stops, polled every 30 seconds while the scene is active.
///
/// Starts from the Nearby list's snapshot, so the screen has departures the
/// moment it is pushed; the first poll replaces them.
@MainActor
@Observable
public final class RouteDirectionModel {
    /// The nearest stop plus up to two "Also nearby" — one request each per poll.
    public static let stopLimit = 3

    /// The route, headsign, and stop set being shown. Header content; stays
    /// fixed between polls so the headsign cannot flicker.
    public private(set) var direction: NearbyRouteDirection
    /// The same route heading the other way, if any nearby stop serves it.
    public private(set) var opposite: NearbyRouteDirection?
    /// Live departures, nearest stop first. Empty when the last good poll
    /// found nothing for this direction in the next 60 minutes.
    public private(set) var stops: [RouteDirectionStop]
    public private(set) var updatedAt: Date
    /// A later poll failed; `stops` and `updatedAt` are the last good ones.
    public private(set) var stale = false

    @ObservationIgnored private let host: WatchAppHost
    @ObservationIgnored private let origin: CLLocation
    @ObservationIgnored private let snapshotDate: Date
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let loader = NearbyRoutesLoader()
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(
        host: WatchAppHost,
        origin: CLLocation,
        direction: NearbyRouteDirection,
        opposite: NearbyRouteDirection?,
        snapshotDate: Date,
        interval: Duration = .seconds(30)
    ) {
        self.host = host
        self.origin = origin
        self.direction = direction
        self.opposite = opposite
        self.stops = Array(direction.stops.prefix(Self.stopLimit))
        self.updatedAt = snapshotDate
        self.snapshotDate = snapshotDate
        self.interval = interval
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        guard let apiService = host.apiService else {
            stale = true
            return
        }

        let polledStops = direction.stops.prefix(Self.stopLimit).map(\.stop)
        let key = direction.key
        pollTask = Task { [weak self, loader, origin, interval] in
            while !Task.isCancelled {
                let result: Result<[NearbyRouteDirection], Error>
                do {
                    result = .success(try await loader.directions(at: polledStops, origin: origin, using: apiService))
                } catch {
                    result = .failure(error)
                }
                guard let self, !Task.isCancelled else { return }
                self.apply(result, for: key)

                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Shows the opposite direction in place, from the Nearby snapshot, and
    /// polls its stops instead.
    public func switchDirection() {
        guard let opposite else { return }
        stopPolling()
        self.opposite = direction
        direction = opposite
        stops = Array(opposite.stops.prefix(Self.stopLimit))
        updatedAt = snapshotDate
        stale = false
        startPolling()
    }

    private func apply(_ result: Result<[NearbyRouteDirection], Error>, for key: RouteDirectionKey) {
        // A poll that started before `switchDirection` is for the old key.
        guard key == direction.key else { return }
        switch result {
        case .success(let directions):
            stops = directions.first { $0.key == key }?.stops ?? []
            updatedAt = Date()
            stale = false
        case .failure:
            stale = true
        }
    }
}
