//
//  VehicleTrackTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// The estimator end to end through `VehicleTrack`: what a marker shows at each
/// moment, given the fixes so far. Times are seconds after `EstimationFixtures.t0`.
@Suite(.serialized)
struct VehicleTrackTests {
    typealias F = EstimationFixtures

    private func track(_ geometry: TripGeometry = F.tenMetersPerSecond(), tunables: VehicleEstimationTunables = .default) -> VehicleTrack {
        VehicleTrack(geometry: geometry, tunables: tunables)
    }

    private func s(_ track: inout VehicleTrack, at seconds: TimeInterval) -> Double? {
        track.estimate(at: F.t0 + seconds)?.distanceAlongShape
    }

    // MARK: - Extrapolation

    @Test func `No fix, no estimate`() {
        var track = track()
        #expect(track.estimate(at: F.t0) == nil)
    }

    @Test func `One fix advances at the scheduled pace`() {
        var track = track()
        #expect(track.ingest(F.fix(north: 200, at: 0), now: F.t0) == .accepted)
        expectClose(s(&track, at: 0), 200, within: 0.5)
        expectClose(s(&track, at: 10), 300, within: 0.5)
        #expect(track.estimate(at: F.t0 + 10)?.mode == .estimated)
    }

    @Test func `The marker holds at a stop it reaches for the dwell`() {
        var track = track(F.tenMetersPerSecond(extraStops: [500]))
        _ = track.ingest(F.fix(north: 450, at: 0), now: F.t0)
        expectClose(s(&track, at: 5), 500, within: 0.5)
        expectClose(s(&track, at: 15), 500, within: 0.5)
        expectClose(s(&track, at: 20), 500, within: 0.5)
        expectClose(s(&track, at: 25), 550, within: 0.5)
    }

    @Test func `A vehicle already at a stop does not dwell there again`() {
        var track = track(F.tenMetersPerSecond(extraStops: [500]))
        _ = track.ingest(F.fix(north: 495, at: 0), now: F.t0)
        expectClose(s(&track, at: 10), 595, within: 0.5)
    }

    @Test func `Past the horizon the marker freezes where the horizon left it`() {
        var tunables = VehicleEstimationTunables.default
        tunables.horizon = 30
        var track = track(tunables: tunables)
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        expectClose(s(&track, at: 200), 400, within: 0.5)
        #expect(track.estimate(at: F.t0 + 200)?.mode == .frozen)
    }

    @Test func `Extrapolation is capped in distance`() {
        var tunables = VehicleEstimationTunables.default
        tunables.maxExtrapolationMeters = 150
        var track = track(tunables: tunables)
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        expectClose(s(&track, at: 60), 250, within: 0.5)
    }

    @Test func `The estimate never runs off the end of the trip`() {
        var tunables = VehicleEstimationTunables.default
        tunables.terminalZoneMeters = 10
        var track = track(tunables: tunables)
        _ = track.ingest(F.fix(north: 900, at: 0), now: F.t0)
        expectClose(s(&track, at: 60), 1000, within: 0.5)
    }

    @Test func `A first fix older than the horizon is frozen where it was, not advanced`() {
        var track = track()
        _ = track.ingest(F.fix(north: 200, at: 0), now: F.t0 + 300)
        let estimate = track.estimate(at: F.t0 + 300)
        expectClose(estimate?.distanceAlongShape, 200, within: 0.5)
        #expect(estimate?.mode == .frozen)
    }

    // MARK: - Pace

    /// The weight on observed pace 10 s after the newest fix: 0.7, halving every 60 s.
    private static let weightAfter10s = 0.7 * pow(0.5, 10.0 / 60)

    /// The bus covered in 30 s what the schedule gives 15 s: half pace, blended
    /// with the schedule's 1.0 by a weight that decays as the fix ages.
    @Test func `Observed pace scales the scheduled speed`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = track.ingest(F.fix(north: 250, at: 30), now: F.t0 + 30)
        expectClose(s(&track, at: 30), 250, within: 0.5)
        let pace = Self.weightAfter10s * 0.5 + (1 - Self.weightAfter10s)
        expectClose(s(&track, at: 40), 250 + pace * 10 * 10, within: 0.5)
    }

    @Test func `Pace is clamped`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = track.ingest(F.fix(north: 100, at: 30), now: F.t0 + 30)
        // Stationary for 30 s: observed pace 0, clamped to minPace 0.3 before blending.
        let pace = Self.weightAfter10s * 0.3 + (1 - Self.weightAfter10s)
        expectClose(s(&track, at: 40), 100 + pace * 10 * 10, within: 0.5)
    }

    @Test func `Without a schedule, observed speed carries the marker`() {
        var track = track(TripGeometry(shape: F.straightLine(), stopTimes: [], serverTripLength: 1000))
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = track.ingest(F.fix(north: 250, at: 30), now: F.t0 + 30)
        expectClose(s(&track, at: 40), 300, within: 1)
    }

    @Test func `Without a schedule or a second fix there is nothing to extrapolate with`() {
        var track = track(TripGeometry(shape: F.straightLine(), stopTimes: [], serverTripLength: 1000))
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        #expect(track.estimate(at: F.t0 + 10)?.mode == .raw(.noSpeed))
    }

    // MARK: - Terminals

    @Test func `A vehicle waiting at the first stop before departure holds there`() {
        var track = track(F.tenMetersPerSecond())
        // The trip departs at t0 + 0 and is running 60 s late.
        _ = track.ingest(F.fix(north: 10, at: -120, scheduleDeviation: 60), now: F.t0 - 120)
        expectClose(s(&track, at: -60), 10, within: 0.5)
        #expect(track.estimate(at: F.t0 - 60)?.mode == .holding)
    }

    @Test func `A vehicle at the last stop holds there`() {
        var track = track()
        _ = track.ingest(F.fix(north: 980, at: 0), now: F.t0)
        expectClose(s(&track, at: 30), 980, within: 0.5)
        #expect(track.estimate(at: F.t0 + 30)?.mode == .holding)
    }

    // MARK: - Reconciliation

    @Test func `The first estimate snaps; the next one moves`() {
        var track = track()
        _ = track.ingest(F.fix(north: 200, at: 0), now: F.t0)
        #expect(track.estimate(at: F.t0)?.shouldSnap == true)
        #expect(track.estimate(at: F.t0 + 1)?.shouldSnap == false)
    }

    @Test func `A fix ahead of the marker is caught up with over the reconcile duration`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = s(&track, at: 10)                       // shown at 200
        _ = track.ingest(F.fix(north: 300, at: 10), now: F.t0 + 10)

        // The same fixes, never displayed in between: where the marker is headed.
        var reference = self.track()
        _ = reference.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = reference.ingest(F.fix(north: 300, at: 10), now: F.t0 + 10)

        let midway = s(&track, at: 10.75)!
        let target = s(&reference, at: 10.75)!
        #expect(midway > 200 && midway < target)
        #expect(track.estimate(at: F.t0 + 11)?.shouldSnap == false)
        expectClose(s(&track, at: 11.5), s(&reference, at: 11.5)!, within: 0.01)
    }

    @Test func `A fix slightly behind the marker is absorbed`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = s(&track, at: 10)                       // shown at 200
        _ = track.ingest(F.fix(north: 190, at: 10), now: F.t0 + 10)
        let shown = s(&track, at: 10)!
        #expect(shown >= 200)
    }

    /// The same fixes, never displayed in between: where the marker is headed.
    private func reference(_ fixes: [(north: Double, at: TimeInterval)], geometry: TripGeometry? = nil) -> VehicleTrack {
        var reference = geometry.map { track($0) } ?? track()
        for fix in fixes { _ = reference.ingest(F.fix(north: fix.north, at: fix.at), now: F.t0 + fix.at) }
        return reference
    }

    @Test func `A fix behind the marker rewinds it along the shape`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = s(&track, at: 10)                       // shown at 200
        _ = track.ingest(F.fix(north: 150, at: 10), now: F.t0 + 10)
        var reference = reference([(100, 0), (150, 10)])

        let start = track.estimate(at: F.t0 + 10)
        #expect(start?.isRewinding == true)
        expectClose(start?.distanceAlongShape, 200, within: 0.5)
        // 50 m back takes the shortest rewind, 1.5 s.
        let midway = track.estimate(at: F.t0 + 10.75)
        #expect(midway?.isRewinding == true)
        #expect(midway?.shouldSnap == false)
        let target = s(&reference, at: 10.75)!
        #expect(midway!.distanceAlongShape! < 200 && midway!.distanceAlongShape! > target)

        let done = track.estimate(at: F.t0 + 11.5)
        #expect(done?.isRewinding == false)
        expectClose(done?.distanceAlongShape, s(&reference, at: 11.5)!, within: 0.01)
    }

    @Test(arguments: [(200.0, 2.0), (300.0, 3.0), (600.0, 3.0)])
    func `A rewind takes longer the farther it goes, up to 3 s`(back: Double, duration: TimeInterval) {
        let geometry = TripGeometry(shape: F.straightLine(), stopTimes: [], serverTripLength: 1000)
        var track = track(geometry)
        _ = track.ingest(F.fix(north: 700, at: 0), now: F.t0)
        _ = s(&track, at: 0)                        // shown at 700, no speed yet
        _ = track.ingest(F.fix(north: 700 - back, at: 1), now: F.t0 + 1)

        #expect(track.estimate(at: F.t0 + 1 + duration - 0.05)?.isRewinding == true)
        let done = track.estimate(at: F.t0 + 1 + duration + 0.01)
        #expect(done?.isRewinding == false)
        #expect(done?.shouldSnap == false)
    }

    @Test func `A fix far behind the marker rewinds rather than snapping`() {
        var track = track()
        _ = track.ingest(F.fix(north: 400, at: 0), now: F.t0)
        _ = s(&track, at: 1)
        _ = track.ingest(F.fix(north: 100, at: 1), now: F.t0 + 1)

        let start = track.estimate(at: F.t0 + 1)
        #expect(start?.shouldSnap == false)
        #expect(start?.isRewinding == true)
        let done = track.estimate(at: F.t0 + 4)
        #expect(done?.isRewinding == false)
        #expect(done!.distanceAlongShape! < 200)
    }

    @Test func `Without animated corrections a fix behind the marker jumps there`() {
        var track = track()
        track.animatesCorrections = false
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        _ = s(&track, at: 10)                       // shown at 200
        _ = track.ingest(F.fix(north: 150, at: 10), now: F.t0 + 10)
        var reference = reference([(100, 0), (150, 10)])

        let estimate = track.estimate(at: F.t0 + 10)
        #expect(estimate?.shouldSnap == true)
        #expect(estimate?.isRewinding == false)
        expectClose(estimate?.distanceAlongShape, s(&reference, at: 10)!, within: 0.01)
    }

    @Test func `The marker moves backward only by rewinding or snapping`() {
        var generator = SeededGenerator(seed: 1312)
        for _ in 0..<100 {
            var track = track(F.tenMetersPerSecond(extraStops: [300, 600]))
            var truth = Double.random(in: 0...200, using: &generator)
            var time = 0.0
            var shown: Double?
            var wasRewinding = false
            for step in 0..<60 {
                time += 1
                if step % 15 == 0 {
                    truth = min(truth + Double.random(in: -60...160, using: &generator), 950)
                    _ = track.ingest(F.fix(north: max(truth, 0), at: time), now: F.t0 + time)
                }
                guard let estimate = track.estimate(at: F.t0 + time), let s = estimate.distanceAlongShape else { continue }
                // Sampled once a second, a rewind's last leg lands on the frame after it.
                if let shown, !estimate.shouldSnap, !estimate.isRewinding, !wasRewinding {
                    #expect(s >= shown - 0.001, "moved back from \(shown) to \(s) at \(time)")
                }
                shown = s
                wasRewinding = estimate.isRewinding
            }
        }
    }

    // MARK: - Ingest

    @Test func `The same fix twice is a duplicate`() {
        var track = track()
        #expect(track.ingest(F.fix(north: 100, at: 0), now: F.t0) == .accepted)
        #expect(track.ingest(F.fix(north: 100, at: 0), now: F.t0 + 15) == .duplicate)
    }

    @Test func `An older fix than the latest is stale`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 30), now: F.t0 + 30)
        #expect(track.ingest(F.fix(north: 50, at: 0), now: F.t0 + 31) == .stale)
    }

    @Test func `A different vehicle resets the track and snaps`() {
        var track = track()
        _ = track.ingest(F.fix(north: 600, at: 0), now: F.t0)
        _ = s(&track, at: 1)
        #expect(track.ingest(F.fix(north: 100, at: 2, vehicleID: "v2"), now: F.t0 + 2) == .reset)
        let estimate = track.estimate(at: F.t0 + 2)
        #expect(estimate?.shouldSnap == true)
        expectClose(estimate?.distanceAlongShape, 100, within: 0.5)
    }

    @Test func `An off-shape fix shows raw, and the next on-shape fix resumes`() {
        var track = track()
        _ = track.ingest(F.fix(north: 100, at: 0), now: F.t0)
        #expect(track.ingest(F.fix(north: 300, east: 200, at: 30), now: F.t0 + 30) == .offShape)
        let raw = track.estimate(at: F.t0 + 31)
        #expect(raw?.mode == .raw(.offShape))
        #expect(raw?.distanceAlongShape == nil)
        expectClose(raw?.coordinate.longitude, F.point(north: 300, east: 200).longitude, within: 1e-9)

        #expect(track.ingest(F.fix(north: 400, at: 60), now: F.t0 + 60) == .accepted)
        let resumed = track.estimate(at: F.t0 + 60)
        #expect(resumed?.mode == .estimated)
        #expect(resumed?.shouldSnap == true)
    }

    // MARK: - Output

    @Test func `Heading follows the shape, in OBA's orientation too`() throws {
        var track = track(TripGeometry(shape: ShapeLine(coordinates: [F.origin, F.point(north: 0, east: 1000)])!, stopTimes: [], serverTripLength: nil))
        _ = track.ingest(F.fix(north: 0, east: 100, at: 0), now: F.t0)
        let maybeEstimate = track.estimate(at: F.t0)
        let estimate = try #require(maybeEstimate)
        expectClose(estimate.bearingDegrees, 90, within: 0.01)
        // OBA's 0° is east, counter-clockwise.
        expectClose(estimate.obaOrientation, 0, within: 0.01)
    }

    @Test(arguments: [
        (VehicleEstimate.Mode.estimated, true), (.holding, true), (.frozen, true),
        (.raw(.offShape), false), (.raw(.noSpeed), false),
    ])
    func `Every mode but raw draws a position the device worked out`(mode: VehicleEstimate.Mode, isEstimated: Bool) {
        let estimate = TripMapFocusFixture.estimate(at: F.origin, fixAge: 300, mode: mode)
        #expect(estimate.isEstimatedPosition == isEstimated)
    }

    @Test func `Progress is the fraction of the shape behind the marker`() {
        var track = track()
        _ = track.ingest(F.fix(north: 250, at: 0), now: F.t0)
        expectClose(track.estimate(at: F.t0)?.progress, 0.25, within: 0.001)
    }

    @Test func `Fix age is measured against the estimate's clock and never negative`() {
        var track = track()
        _ = track.ingest(F.fix(north: 250, at: 10), now: F.t0)
        expectClose(track.estimate(at: F.t0)?.fixAge, 0, within: 0.001)
        expectClose(track.estimate(at: F.t0 + 40)?.fixAge, 30, within: 0.001)
    }
}

/// A deterministic `RandomNumberGenerator` (SplitMix64) for property-style tests.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
