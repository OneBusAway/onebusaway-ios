//
//  StopVehicleEstimation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Estimates where the buses arriving at a stop are now, each on its own trip's
/// shape with its own trip's schedule.
///
/// Shared by both of a stop's maps: `StopRouteFocusMapLayer` on the map tab and
/// `StopFocusMapDisplayModel` on the panel. Each hands it the vehicles it draws on
/// every arrivals refresh, and draws a vehicle at `estimates[vehicle.id]` when
/// there is one, or where the feed says when there isn't.
@MainActor
final class StopVehicleEstimation {

    /// Every vehicle's estimate, by `StopRouteFocusModel.DrawnVehicle.id`, once a
    /// second and on every refresh, with the ones before: a vehicle in `previous`
    /// and not in `current` has gone back to the feed. `estimates` already holds
    /// `current`.
    var onEstimates: ((_ current: [String: VehicleEstimate], _ previous: [String: VehicleEstimate]) -> Void)?

    /// The latest estimates. Empty while estimation is off or stopped.
    private(set) var estimates: [String: VehicleEstimate] = [:]

    private let driver: VehicleEstimationDriver
    private let shapeCache: ShapeCache
    private let tripSchedules: TripScheduleCache

    private var gatheringTask: Task<Void, Never>?
    /// Bumped by every refresh and stop, so a gathering that finishes late can't
    /// restart estimation the owner has since moved past.
    private var generation = 0
    /// Whether `stop()` has run since the last `refresh`, so stopping again (every
    /// arrivals refresh while the panel's stop is suppressed) publishes nothing.
    private var isStopped = true

    /// The last server clock handed to the driver: each is recorded once per
    /// response, not once per filter change, or one sample would fill the skew
    /// median.
    private var recordedServerClock: ServerClockSample?

    init(driver: VehicleEstimationDriver, shapeCache: ShapeCache, tripSchedules: TripScheduleCache) {
        self.driver = driver
        self.shapeCache = shapeCache
        self.tripSchedules = tripSchedules
        driver.onEstimates = { [weak self] estimates in
            guard let self else { return }
            let previous = self.estimates
            self.estimates = estimates
            onEstimates?(estimates, previous)
        }
    }

    /// Estimation behind `FeatureFlags.estimatesVehiclePositionsKey`, read live,
    /// fetching schedules with `apiService`'s `trip-details`.
    ///
    /// - Parameter apiService: Read per fetch, since it changes with the region.
    convenience init(
        userDefaults: UserDefaults,
        shapeCache: ShapeCache,
        apiService: @escaping @Sendable () async -> RESTAPIService?
    ) {
        self.init(
            driver: VehicleEstimationDriver(isEnabled: {
                FeatureFlags.isVehicleEstimationEnabled(userDefaults: userDefaults)
            }),
            shapeCache: shapeCache,
            tripSchedules: TripScheduleCache { request in
                guard let apiService = await apiService() else { throw CancellationError() }
                let details = try await apiService.getTrip(
                    tripID: request.tripID, vehicleID: request.vehicleID, serviceDate: request.serviceDate
                ).entry
                return TripScheduleCache.Schedule(
                    stopTimes: details.stopTimes.compactMap(TripGeometry.StopTime.init),
                    serverTripLength: details.status?.totalDistanceAlongTrip
                )
            }
        )
    }

    // MARK: - Input

    /// Gathers each vehicle's shape and schedule, from their caches or the network,
    /// then estimates the lot. Asynchronous, so a vehicle whose shape or schedule
    /// hasn't arrived stays where the feed says until it has.
    ///
    /// - Parameters:
    ///   - serverClock: The latest arrivals response's. Pass it on every refresh,
    ///     not just the first after the response: one that cancels the gathering
    ///     before the driver had it would lose it otherwise. Recorded once.
    ///   - departure: The departure behind a `DrawnVehicle.departureID`.
    func refresh(
        vehicles: [StopRouteFocusModel.DrawnVehicle],
        serverClock: ServerClockSample?,
        departure: (String) -> ArrivalDeparture?
    ) {
        guard driver.isEnabledNow else {
            // Also stops the tick and any gathering still in flight, which would
            // otherwise resume the driver.
            stop()
            return
        }

        let pending: [Pending] = vehicles.compactMap { vehicle in
            guard let tripID = vehicle.tripID, let shapeID = vehicle.shapeID, !shapeID.isEmpty,
                  let departure = departure(vehicle.departureID),
                  let status = departure.tripStatus else { return nil }
            return Pending(
                vehicleKey: vehicle.id,
                tripID: tripID,
                shapeID: shapeID,
                request: .init(tripID: tripID, vehicleID: departure.vehicleID, serviceDate: departure.serviceDate),
                serverTripLength: status.totalDistanceAlongTrip,
                fix: VehicleFix(tripStatus: status, tripID: tripID)
            )
        }
        let serverClocks = [serverClock].compactMap { $0 }.filter { $0 != recordedServerClock }

        isStopped = false
        generation += 1
        let generation = generation
        gatheringTask?.cancel()
        gatheringTask = Task { [weak self, shapeCache, tripSchedules] in
            let inputs = await Self.inputs(for: pending, shapeCache: shapeCache, tripSchedules: tripSchedules)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            driver.update(inputs, serverClocks: serverClocks)
            // Only once the driver has it: a gathering cancelled first leaves the
            // sample for the next refresh to deliver.
            recordedServerClock = serverClocks.last ?? recordedServerClock
            driver.resume()
        }
    }

    /// Stops ticking and forgets every vehicle; each goes back to the feed.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        generation += 1
        gatheringTask?.cancel()
        gatheringTask = nil
        driver.pause()
        driver.update([])
        estimates.removeAll()
    }

    /// Forgets every schedule: trip IDs are region-scoped.
    func removeAllSchedules() async {
        await tripSchedules.removeAll()
    }

    /// Lets tests wait for the gathering `refresh` started.
    func inputsSettled() async {
        await gatheringTask?.value
    }

    // MARK: - Gathering

    /// What `refresh` knows about a vehicle before its shape and schedule arrive.
    private struct Pending: Sendable {
        let vehicleKey: String
        let tripID: String
        let shapeID: String
        let request: TripScheduleCache.Request
        let serverTripLength: Double
        let fix: VehicleFix?
    }

    /// Every vehicle at once: on a cold cache each is a round trip or two.
    private static func inputs(
        for pending: [Pending],
        shapeCache: ShapeCache,
        tripSchedules: TripScheduleCache
    ) async -> [VehicleEstimationDriver.Input] {
        await withTaskGroup(of: VehicleEstimationDriver.Input?.self) { group in
            for vehicle in pending {
                group.addTask {
                    async let shape = try? shapeCache.coordinates(forShapeID: vehicle.shapeID)
                    // Without its schedule a vehicle can still move at its observed speed.
                    async let schedule = try? tripSchedules.schedule(for: vehicle.request)
                    guard let shape = await shape, shape.count > 1 else { return nil }
                    let fetched = await schedule
                    return VehicleEstimationDriver.Input(
                        vehicleKey: vehicle.vehicleKey,
                        tripID: vehicle.tripID,
                        shape: shape,
                        stopTimes: fetched?.stopTimes ?? [],
                        serverTripLength: vehicle.serverTripLength > 0 ? vehicle.serverTripLength : fetched?.serverTripLength,
                        fixes: [vehicle.fix].compactMap { $0 }
                    )
                }
            }
            var inputs: [VehicleEstimationDriver.Input] = []
            for await input in group {
                if let input { inputs.append(input) }
            }
            return inputs
        }
    }
}
