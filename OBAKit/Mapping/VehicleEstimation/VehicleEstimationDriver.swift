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

/// Runs a `VehicleTrack` for one trip on a 1 Hz tick and hands each estimate to
/// whoever draws the marker.
///
/// Fed by the trip page on every poll (`update`), started and stopped with the
/// page (`resume`, `pause`), and stopped in the background. Publishes `nil` when
/// there is nothing to estimate — the feature is off, the trip has no shape, the
/// vehicle reports no usable fix — which tells the map to draw the reported
/// position as it always has.
@MainActor
final class VehicleEstimationDriver {

    /// Everything one poll knows about the trip.
    struct Input {
        let tripID: String
        let shape: [CLLocationCoordinate2D]
        let stopTimes: [TripGeometry.StopTime]
        /// `TripStatus.totalDistanceAlongTrip`, for rescaling stop distances.
        let serverTripLength: Double?
        /// Every status the poll returned, in any order: the trip page gets one from
        /// the arrival and one from the trip details.
        let fixes: [VehicleFix]
        let serverClocks: [ServerClockSample]
    }

    static let tickInterval: Duration = .seconds(1)
    /// With Reduce Motion on, the marker moves this often, without animating.
    static let reduceMotionStepInterval: TimeInterval = 10

    var onEstimate: ((VehicleEstimate?) -> Void)?

    private(set) var estimate: VehicleEstimate?

    private let isEnabled: () -> Bool
    private let reduceMotion: () -> Bool
    private let clock: any Clock<Duration>
    private let now: () -> Date
    private let tunables: VehicleEstimationTunables

    private var track: VehicleTrack?
    private var geometryKey: GeometryKey?
    private var skew = ClockSkewEstimator()
    private var lastPublishedAt: Date?

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

        observers = [
            notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(true) }
            },
            notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setInBackground(false) }
            }
        ]
    }

    isolated deinit {
        tickTask?.cancel()
    }

    // MARK: - Input

    func update(_ input: Input) {
        guard isEnabled(), let shape = ShapeLine(coordinates: input.shape) else {
            reset()
            return
        }

        input.serverClocks.forEach { skew.record($0) }

        let key = GeometryKey(input: input)
        if key != geometryKey || track == nil {
            geometryKey = key
            let geometry = TripGeometry(shape: shape, stopTimes: input.stopTimes, serverTripLength: input.serverTripLength)
            track = VehicleTrack(geometry: geometry, tunables: tunables)
        }

        let serverNow = skew.serverNow(deviceNow: now())
        for fix in input.fixes.filter({ $0.tripID == input.tripID }).sorted(by: { $0.fixTime < $1.fixTime }) {
            _ = track?.ingest(fix, now: serverNow)
        }
        publish(force: true)
    }

    private func reset() {
        track = nil
        geometryKey = nil
        lastPublishedAt = nil
        estimate = nil
        onEstimate?(nil)
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
                do { try await clock.sleep(for: Self.tickInterval) } catch { return }
                self?.publish(force: false)
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func publish(force: Bool) {
        guard var track, track.hasFix else {
            if estimate != nil || force {
                estimate = nil
                onEstimate?(nil)
            }
            return
        }

        let deviceNow = now()
        if !force, reduceMotion(), let lastPublishedAt,
           deviceNow.timeIntervalSince(lastPublishedAt) < Self.reduceMotionStepInterval {
            return
        }

        let next = track.estimate(at: skew.serverNow(deviceNow: deviceNow))
        self.track = track
        lastPublishedAt = deviceNow
        estimate = next
        onEstimate?(next)
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
