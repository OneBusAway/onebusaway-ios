//
//  VehicleTrack.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// One vehicle on one trip: its recent fixes, and where its marker was last shown.
///
/// Feed it every status as it arrives (`ingest`) and ask where to draw the marker
/// as often as the map redraws (`estimate`). Both take `now` on the *server's*
/// clock; see `ClockSkewEstimator`. The algorithm is in
/// `docs/vehicle-position-estimation.md` §4:
///
/// 1. Each fix is placed on the shape (`ShapeLine.project`), using where the marker
///    is as the hint on shapes that double back.
/// 2. From the newest fix, the marker advances at the schedule's speed for each stretch
///    of the trip, scaled by the vehicle's observed pace against the schedule, pausing
///    `dwell` at each stop, for at most `horizon` seconds and `maxExtrapolationMeters`.
/// 3. A new fix ahead of the marker is caught up with over `reconcileDuration`; one
///    behind it rewinds the marker back along the shape to it, over
///    `rewindMinDuration`…`rewindMaxDuration`. Otherwise the marker never moves
///    backward.
public struct VehicleTrack: Sendable {

    public enum IngestResult: Sendable, Equatable {
        case accepted
        /// The same fix again: polls outpace the feed, and the trip page gets each
        /// status twice per poll.
        case duplicate
        /// Older than the newest fix.
        case stale
        /// Too far from the shape; the marker shows the raw fix until one is back on it.
        case offShape
        /// A different vehicle or trip: history was discarded, and the marker snaps.
        case reset
    }

    public let geometry: TripGeometry
    public var tunables: VehicleEstimationTunables
    /// Whether a fix behind the marker rewinds it there; off, it jumps. Off for
    /// Reduce Motion.
    public var animatesCorrections = true

    private struct Anchor: Sendable {
        let fix: VehicleFix
        let s: Double
        /// Server time when the fix arrived.
        let receivedAt: Date
    }

    private enum Reconcile: Sendable {
        case none
        case catchUp(from: Double, start: Date)
        case rewind(from: Double, start: Date, duration: TimeInterval)
    }

    /// Oldest first: the two that measure a pace.
    private var anchors: [Anchor] = []
    private var latestFix: VehicleFix?
    private var isOffShape = false
    private var shownS: Double?
    private var needsSnap = true
    private var reconcile = Reconcile.none

    public init(geometry: TripGeometry, tunables: VehicleEstimationTunables = .default) {
        self.geometry = geometry
        self.tunables = tunables
    }

    public var hasFix: Bool { latestFix != nil }

    // MARK: - Ingest

    public mutating func ingest(_ fix: VehicleFix, now: Date) -> IngestResult {
        var wasReset = false
        if let latest = latestFix {
            if Self.isDifferentVehicle(latest, fix) {
                resetHistory()
                wasReset = true
            } else if fix.fixTime == latest.fixTime {
                return .duplicate
            } else if fix.fixTime < latest.fixTime {
                return .stale
            }
        }
        latestFix = fix

        let hint = shownS ?? anchors.last?.s
        guard let projection = geometry.shape.project(
            fix.coordinate,
            maxOffset: tunables.maxProjectionMeters,
            hint: hint,
            maxBackwardJump: tunables.maxBackwardJumpMeters
        ) else {
            isOffShape = true
            return wasReset ? .reset : .offShape
        }

        if isOffShape {
            isOffShape = false
            snapNext()
        }

        let anchor = Anchor(fix: fix, s: projection.distanceAlongShape, receivedAt: now)
        anchors.append(anchor)
        if anchors.count > 2 { anchors.removeFirst(anchors.count - 2) }

        reconcile(with: anchor, now: now)
        return wasReset ? .reset : .accepted
    }

    /// Decides how the marker gets from where it is shown to where `anchor` puts it.
    private mutating func reconcile(with anchor: Anchor, now: Date) {
        guard let shown = shownS, !needsSnap else { return }
        let delta = rawEstimate(at: now).s - shown
        if delta > tunables.snapForwardMeters || delta < -tunables.paceResetBehindMeters {
            // A pace measured across a jump this size would be nonsense.
            anchors = [anchor]
        }
        if delta > tunables.snapForwardMeters {
            snapNext()
        } else if delta >= 0 {
            reconcile = .catchUp(from: shown, start: now)
        } else if delta >= -tunables.backwardToleranceMeters {
            // The monotonic clamp in `estimate` waits it out.
            reconcile = .none
        } else if animatesCorrections {
            let duration = min(max(-delta / tunables.rewindSpeed, tunables.rewindMinDuration), tunables.rewindMaxDuration)
            reconcile = .rewind(from: shown, start: now, duration: duration)
        } else {
            snapNext()
        }
    }

    private static func isDifferentVehicle(_ a: VehicleFix, _ b: VehicleFix) -> Bool {
        if a.tripID != b.tripID { return true }
        if let first = a.vehicleID, let second = b.vehicleID { return first != second }
        return false
    }

    private mutating func resetHistory() {
        anchors.removeAll()
        latestFix = nil
        isOffShape = false
        snapNext()
    }

    private mutating func snapNext() {
        shownS = nil
        needsSnap = true
        reconcile = .none
    }

    // MARK: - Estimate

    /// Where to draw the marker at `now`, or `nil` before the first fix.
    public mutating func estimate(at now: Date) -> VehicleEstimate? {
        guard let latest = latestFix else { return nil }
        let age = max(0, now.timeIntervalSince(latest.fixTime))

        if isOffShape || anchors.isEmpty {
            snapNext()
            return VehicleEstimate(
                coordinate: latest.coordinate, distanceAlongShape: nil, progress: nil, bearingDegrees: nil,
                fixTime: latest.fixTime, fixAge: age, mode: .raw(.offShape), shouldSnap: false
            )
        }

        let raw = rawEstimate(at: now)
        var s = raw.s
        let snap = needsSnap
        // Moving back, or just arrived back: the never-backward clamp stands aside.
        var isRewinding = false, finishedRewind = false

        switch reconcile {
        case .none:
            break
        case let .catchUp(from, start):
            let progress = now.timeIntervalSince(start) / tunables.reconcileDuration
            if progress >= 1 {
                reconcile = .none
            } else {
                s = from + (raw.s - from) * max(progress, 0)
            }
        case let .rewind(from, start, duration):
            let progress = now.timeIntervalSince(start) / duration
            if progress >= 1 {
                reconcile = .none
                finishedRewind = true
            } else {
                s = from + (raw.s - from) * max(progress, 0)
                isRewinding = true
            }
        }

        if !snap, !isRewinding, !finishedRewind, let shown = shownS { s = max(s, shown) }
        shownS = s
        needsSnap = false

        let location = geometry.shape.point(at: s)
        return VehicleEstimate(
            coordinate: location.coordinate,
            distanceAlongShape: s,
            progress: s / geometry.shape.length,
            bearingDegrees: location.bearingDegrees,
            fixTime: latest.fixTime,
            fixAge: age,
            mode: raw.mode,
            shouldSnap: snap,
            isRewinding: isRewinding
        )
    }

    /// Where the newest fix puts the vehicle at `now`, before reconciliation.
    private func rawEstimate(at now: Date) -> (s: Double, mode: VehicleEstimate.Mode) {
        let newest = anchors[anchors.count - 1]
        let length = geometry.shape.length

        if newest.s >= length - tunables.terminalZoneMeters {
            return (newest.s, .holding)
        }
        if let first = geometry.stops.first,
           newest.s <= first.distanceAlongShape + tunables.terminalZoneMeters,
           now < first.departure + newest.fix.scheduleDeviation {
            return (newest.s, .holding)
        }
        // Already past the horizon when it arrived: with nothing newer to go on,
        // advancing it would be the riskiest guess the estimator can make.
        if newest.receivedAt.timeIntervalSince(newest.fix.fixTime) > tunables.horizon {
            return (newest.s, .frozen)
        }

        let age = max(0, now.timeIntervalSince(newest.fix.fixTime))
        let duration = min(age, tunables.horizon)
        let mode: VehicleEstimate.Mode = age > tunables.horizon ? .frozen : .estimated

        if geometry.hasSchedule {
            return (walk(from: newest.s, for: duration, pace: pace(at: now)), mode)
        }
        if let speed = observedSpeed() {
            let limit = min(length, newest.s + tunables.maxExtrapolationMeters)
            return (min(newest.s + speed * duration, limit), mode)
        }
        return (newest.s, .raw(.noSpeed))
    }

    /// The vehicle's pace against the schedule (1 = on schedule pace), blended toward
    /// 1 as the newest fix ages.
    private func pace(at now: Date) -> Double {
        guard anchors.count >= 2 else { return 1 }
        let older = anchors[anchors.count - 2], newer = anchors[anchors.count - 1]
        let interval = newer.fix.fixTime.timeIntervalSince(older.fix.fixTime)
        guard interval >= tunables.minObservationInterval, interval <= tunables.maxObservationInterval,
              let olderTime = geometry.scheduledTime(at: older.s),
              let newerTime = geometry.scheduledTime(at: newer.s) else { return 1 }

        let observed = min(max((newerTime - olderTime) / interval, tunables.minPace), tunables.maxPace)
        let age = max(0, now.timeIntervalSince(newer.fix.fixTime))
        let weight = tunables.observedWeight * pow(0.5, age / tunables.observedHalfLife)
        return weight * observed + (1 - weight)
    }

    /// Meters per second between the last two fixes, for a trip without a schedule.
    private func observedSpeed() -> Double? {
        guard anchors.count >= 2 else { return nil }
        let older = anchors[anchors.count - 2], newer = anchors[anchors.count - 1]
        let interval = newer.fix.fixTime.timeIntervalSince(older.fix.fixTime)
        guard interval >= tunables.minObservationInterval, interval <= tunables.maxObservationInterval else { return nil }
        return min(max((newer.s - older.s) / interval, 0), tunables.maxSpeed)
    }

    /// Advances from `start` for `duration` seconds at `pace` times the schedule's
    /// speed, pausing `dwell` at each stop reached. O(stops crossed).
    private func walk(from start: Double, for duration: TimeInterval, pace: Double) -> Double {
        let limit = min(geometry.shape.length, start + tunables.maxExtrapolationMeters)
        var stopIndex = geometry.stops.firstIndex { $0.distanceAlongShape > start + tunables.dwellMinApproachMeters }
        var s = start
        var remaining = duration

        while remaining > 0, s < limit {
            guard let scheduled = geometry.scheduledSpeed(at: s) else { break }
            let speed = min(pace * scheduled, tunables.maxSpeed)
            guard speed > 0 else { break }

            var target = limit
            if let spanEnd = geometry.scheduledSpanEnd(after: s) { target = min(target, spanEnd) }
            var reachesStop = false
            if let index = stopIndex, geometry.stops[index].distanceAlongShape <= target {
                target = geometry.stops[index].distanceAlongShape
                reachesStop = true
            }

            let needed = (target - s) / speed
            if needed >= remaining {
                s += speed * remaining
                break
            }
            s = target
            remaining -= needed
            if reachesStop, let index = stopIndex {
                remaining -= tunables.dwell
                stopIndex = index + 1 < geometry.stops.count ? index + 1 : nil
            }
        }
        return min(s, limit)
    }
}
