//
//  VehicleEstimationDriver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore
import UIKit

/// Runs a `VehicleTrack` per vehicle on a 1 Hz tick and hands the estimates to
/// whoever draws the markers: one vehicle for the trip page, one per arriving bus
/// for the stop's map.
///
/// Fed on every poll (`update`), started and stopped with its screen (`resume`,
/// `pause`), and stopped in the background. A vehicle with nothing to estimate —
/// the feature is off, its trip has no shape, it reports no usable fix — has no
/// estimate, which tells the map to draw its reported position as it always has.
@MainActor
final class VehicleEstimationDriver {

    /// Everything one poll knows about one vehicle's trip.
    struct Input: Sendable {
        /// Which marker this is. Stable across polls for the same vehicle.
        let vehicleKey: String
        let tripID: String
        let shape: [CLLocationCoordinate2D]
        let stopTimes: [TripGeometry.StopTime]
        /// `TripStatus.totalDistanceAlongTrip`, for rescaling stop distances.
        let serverTripLength: Double?
        /// Every status the poll returned, in any order: the trip page gets one from
        /// the arrival and one from the trip details.
        let fixes: [VehicleFix]
    }

    static let tickInterval: Duration = .seconds(1)
    /// While a marker rewinds, ticks come this often, so it follows the shape's
    /// curves back rather than cutting across them.
    static let rewindFrameInterval: Duration = .milliseconds(33)
    /// With Reduce Motion on, the marker moves this often, without animating.
    static let reduceMotionStepInterval: TimeInterval = 10

    /// Every vehicle's estimate, by `Input.vehicleKey`, on every update and tick.
    var onEstimates: (([String: VehicleEstimate]) -> Void)?

    /// For a single vehicle: its estimate, or `nil`.
    var onEstimate: ((VehicleEstimate?) -> Void)?

    private let isEnabled: () -> Bool
    private let reduceMotion: () -> Bool
    private let clock: any Clock<Duration>
    private let now: () -> Date
    private let tunables: VehicleEstimationTunables

    private struct Vehicle {
        var track: VehicleTrack
        let geometryKey: GeometryKey
    }

    private var vehicles: [String: Vehicle] = [:]
    /// The key `onEstimate` reports: the only vehicle, when there is one.
    private var singleKey: String?
    private var skew = ClockSkewEstimator()
    private var lastPublishedAt: Date?
    /// Whether the last estimates had a marker rewinding: ticks at frame rate.
    private var isRewinding = false

    private var tickTask: Task<Void, Never>?
    /// Whether the page wants ticks; the background suspends them without changing it.
    private var isResumed = false
    private var isInBackground = false
    private var observers: [NSObjectProtocol] = []

    init(
        isEnabled: @escaping () -> Bool,
        reduceMotion: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping () -> Date = Date.init,
        tunables: VehicleEstimationTunables = .default,
        notificationCenter: NotificationCenter = .default
    ) {
        self.isEnabled = isEnabled
        self.reduceMotion = reduceMotion
        self.clock = clock
        self.now = now
        self.tunables = tunables
        self.notificationCenter = notificationCenter

        observers = [
            notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(true) }
            },
            notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(false) }
            }
        ]
    }

    private let notificationCenter: NotificationCenter

    isolated deinit {
        tickTask?.cancel()
        // Block-based observers stay registered until removed.
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    /// Whether estimation is on, for callers deciding whether to fetch its inputs.
    var isEnabledNow: Bool { isEnabled() }

    // MARK: - Input

    func update(_ input: Input, serverClocks: [ServerClockSample] = []) {
        update([input], serverClocks: serverClocks)
    }

    /// Replaces the set of vehicles with `inputs`: one left out is dropped.
    ///
    /// - Parameter serverClocks: What the poll's responses said the time was.
    func update(_ inputs: [Input], serverClocks: [ServerClockSample] = []) {
        singleKey = inputs.count == 1 ? inputs[0].vehicleKey : nil
        guard isEnabled() else {
            vehicles.removeAll()
            lastPublishedAt = nil
            publish(force: true)
            return
        }

        serverClocks.forEach { skew.record($0) }
        let serverNow = skew.serverNow(deviceNow: now())

        var next: [String: Vehicle] = [:]
        for input in inputs {
            let key = GeometryKey(input: input)
            var vehicle: Vehicle
            if let existing = vehicles[input.vehicleKey], existing.geometryKey == key {
                vehicle = existing
            } else {
                // Measuring the shape is the only O(points) work here: done only
                // when the trip or its shape changes, not on every poll.
                guard let shape = ShapeLine(coordinates: input.shape) else { continue }
                let geometry = TripGeometry(shape: shape, stopTimes: input.stopTimes, serverTripLength: input.serverTripLength)
                vehicle = Vehicle(track: VehicleTrack(geometry: geometry, tunables: tunables), geometryKey: key)
            }
            vehicle.track.animatesCorrections = !reduceMotion()
            for fix in input.fixes.sorted(by: { $0.fixTime < $1.fixTime }) {
                _ = vehicle.track.ingest(fix, now: serverNow)
            }
            next[input.vehicleKey] = vehicle
        }
        vehicles = next
        publish(force: true)
    }

    // MARK: - Ticking

    func resume() {
        isResumed = true
        startTickingIfNeeded()
    }

    func pause() {
        isResumed = false
        stopTicking()
    }

    private func setInBackground(_ isInBackground: Bool) {
        self.isInBackground = isInBackground
        if isInBackground { stopTicking() } else { startTickingIfNeeded() }
    }

    private func startTickingIfNeeded() {
        guard isResumed, !isInBackground, tickTask == nil else { return }
        tickTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                let interval = self?.isRewinding == true ? Self.rewindFrameInterval : Self.tickInterval
                do { try await clock.sleep(for: interval) } catch { return }
                self?.publish(force: false)
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func publish(force: Bool) {
        let deviceNow = now()
        if !force, vehicles.isEmpty { return }
        if !force, reduceMotion(), let lastPublishedAt,
           deviceNow.timeIntervalSince(lastPublishedAt) < Self.reduceMotionStepInterval {
            return
        }

        let serverNow = skew.serverNow(deviceNow: deviceNow)
        var next: [String: VehicleEstimate] = [:]
        for key in vehicles.keys {
            next[key] = vehicles[key]?.track.estimate(at: serverNow)
        }
        lastPublishedAt = deviceNow
        let startsRewinding = !isRewinding && next.values.contains { $0.isRewinding }
        isRewinding = next.values.contains { $0.isRewinding }
        if startsRewinding, tickTask != nil {
            // The tick asleep for a second would miss most of the rewind.
            stopTicking()
            startTickingIfNeeded()
        }
        onEstimates?(next)
        onEstimate?(singleKey.flatMap { next[$0] })
    }

    /// How long a marker takes to glide to `estimate`: until the next one arrives.
    static func glideDuration(for estimate: VehicleEstimate) -> TimeInterval {
        (estimate.isRewinding ? rewindFrameInterval : tickInterval).timeInterval
    }

    /// What, when it changes, means the shape or schedule did: a new trip, or the
    /// shape or stop times arriving after the first poll.
    private struct GeometryKey: Equatable {
        let tripID: String
        let shapeCount: Int
        let stopCount: Int
        let serverTripLength: Double?

        init(input: Input) {
            tripID = input.tripID
            shapeCount = input.shape.count
            stopCount = input.stopTimes.count
            serverTripLength = input.serverTripLength
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
