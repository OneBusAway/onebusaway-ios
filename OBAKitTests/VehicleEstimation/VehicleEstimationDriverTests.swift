//
//  VehicleEstimationDriverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class VehicleEstimationDriverTests {
    typealias F = EstimationFixtures

    /// The device clock, which the tests move by hand alongside `clock`.
    private final class DeviceClock {
        var now = EstimationFixtures.t0
    }

    private let clock = TestClock()
    private let device = DeviceClock()
    private var isEnabled = true
    private var reduceMotion = false
    private let notificationCenter = NotificationCenter()
    private var published: [VehicleEstimate?] = []
    private lazy var driver: VehicleEstimationDriver = {
        let driver = VehicleEstimationDriver(
            isEnabled: { [unowned self] in isEnabled },
            reduceMotion: { [unowned self] in reduceMotion },
            clock: clock,
            now: { [unowned self] in device.now },
            notificationCenter: notificationCenter
        )
        driver.onEstimate = { [unowned self] in published.append($0) }
        return driver
    }()

    private func input(
        tripID: String = "trip",
        vehicleKey: String? = nil,
        fixes: [VehicleFix] = [F.fix(north: 200, at: 0)]
    ) -> VehicleEstimationDriver.Input {
        VehicleEstimationDriver.Input(
            vehicleKey: vehicleKey ?? tripID,
            tripID: tripID,
            shape: F.straightLine().coordinates,
            stopTimes: [F.stop(0, at: 0), F.stop(1000, at: 100)],
            serverTripLength: 1000,
            fixes: fixes
        )
    }

    /// Moves both clocks, then lets the tick that wakes run.
    private func advance(_ seconds: Int) async {
        let before = published.count
        device.now += TimeInterval(seconds)
        clock.advance(by: .seconds(seconds))
        await poll(until: { self.published.count > before }, "a tick should publish")
    }

    // MARK: -

    @Test func `An update publishes an estimate straight away`() {
        driver.update(input())
        let estimate = published.last??.distanceAlongShape
        expectClose(estimate, 200, within: 0.5)
        #expect(published.last??.shouldSnap == true)
    }

    @Test func `Turned off, it publishes nothing to draw`() {
        isEnabled = false
        driver.update(input())
        #expect(published.count == 1)
        #expect(published.last! == nil)
    }

    @Test func `Turning it off clears a drawn estimate`() {
        driver.update(input())
        isEnabled = false
        driver.update(input())
        #expect(published.last! == nil)
    }

    @Test func `Without a fix it can use, it publishes nothing to draw`() {
        driver.update(input(fixes: []))
        #expect(published.last! == nil)
    }

    @Test func `Once resumed it ticks every second`() async {
        driver.update(input())
        driver.resume()
        await poll(until: { self.clock.sleeperCount == 1 })
        await advance(1)
        expectClose(published.last??.distanceAlongShape, 210, within: 0.5)
        #expect(published.last??.shouldSnap == false)
        await advance(1)
        expectClose(published.last??.distanceAlongShape, 220, within: 0.5)
    }

    @Test func `Paused, it stops ticking`() async {
        driver.update(input())
        driver.resume()
        await poll(until: { self.clock.sleeperCount == 1 })
        driver.pause()
        await poll(until: { self.clock.sleeperCount == 0 }, "pausing should cancel the tick")
    }

    @Test func `It stops ticking in the background and starts again in the foreground`() async {
        driver.update(input())
        driver.resume()
        await poll(until: { self.clock.sleeperCount == 1 })
        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await poll(until: { self.clock.sleeperCount == 0 })
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await poll(until: { self.clock.sleeperCount == 1 })
    }

    @Test func `A paused driver is not woken by the foreground`() async {
        driver.update(input())
        notificationCenter.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await spin(0.05)
        #expect(clock.sleeperCount == 0)
    }

    @Test func `With Reduce Motion on, the marker steps every ten seconds`() async {
        reduceMotion = true
        driver.update(input())
        driver.resume()
        let afterUpdate = published.count
        for _ in 0..<9 {
            await poll(until: { self.clock.sleeperCount == 1 })
            device.now += 1
            clock.advance(by: .seconds(1))
        }
        await poll(until: { self.clock.sleeperCount == 1 })
        #expect(published.count == afterUpdate)
        await advance(1)
        expectClose(published.last??.distanceAlongShape, 300, within: 0.5)
    }

    @Test func `A new trip starts over with a snap`() {
        driver.update(input())
        device.now += 5
        driver.update(input(tripID: "other", fixes: [F.fix(north: 600, at: 5, tripID: "other")]))
        expectClose(published.last??.distanceAlongShape, 600, within: 0.5)
        #expect(published.last??.shouldSnap == true)
    }

    @Test func `A device clock running ahead is corrected`() {
        // The device is 30 s ahead of the server, so a fix the device thinks is 40 s
        // old is 10 s old.
        device.now = F.t0 + 40
        let sample = ServerClockSample(serverTime: F.t0 + 10, receivedAt: F.t0 + 40)
        driver.update(input(), serverClocks: [sample])
        expectClose(published.last??.fixAge, 10, within: 0.001)
    }

    // MARK: - Several vehicles

    @Test func `Several vehicles are estimated at once, each by its key`() {
        var estimates: [String: VehicleEstimate] = [:]
        driver.onEstimates = { estimates = $0 }

        driver.update([
            input(tripID: "a", vehicleKey: "bus 1", fixes: [F.fix(north: 100, at: 0, vehicleID: "bus 1", tripID: "a")]),
            input(tripID: "b", vehicleKey: "bus 2", fixes: [F.fix(north: 500, at: 0, vehicleID: "bus 2", tripID: "b")])
        ])

        expectClose(estimates["bus 1"]?.distanceAlongShape, 100, within: 0.5)
        expectClose(estimates["bus 2"]?.distanceAlongShape, 500, within: 0.5)
    }

    @Test func `A vehicle left out of an update stops being estimated`() {
        var estimates: [String: VehicleEstimate] = [:]
        driver.onEstimates = { estimates = $0 }
        driver.update([
            input(tripID: "a", vehicleKey: "bus 1", fixes: [F.fix(north: 100, at: 0, vehicleID: "bus 1", tripID: "a")]),
            input(tripID: "b", vehicleKey: "bus 2", fixes: [F.fix(north: 500, at: 0, vehicleID: "bus 2", tripID: "b")])
        ])

        driver.update([input(tripID: "b", vehicleKey: "bus 2", fixes: [F.fix(north: 500, at: 0, vehicleID: "bus 2", tripID: "b")])])

        #expect(estimates["bus 1"] == nil)
        #expect(estimates["bus 2"] != nil)
    }

    @Test func `A vehicle keeps its history across updates`() {
        var estimates: [String: VehicleEstimate] = [:]
        driver.onEstimates = { estimates = $0 }
        driver.update([input(tripID: "a", vehicleKey: "bus 1", fixes: [F.fix(north: 100, at: 0, vehicleID: "bus 1", tripID: "a")])])
        device.now += 15
        driver.update([input(tripID: "a", vehicleKey: "bus 1", fixes: [F.fix(north: 100, at: 0, vehicleID: "bus 1", tripID: "a")])])
        // The same fix again: not a new vehicle, so no snap, and it has moved on.
        #expect(estimates["bus 1"]?.shouldSnap == false)
        expectClose(estimates["bus 1"]?.distanceAlongShape, 250, within: 0.5)
    }
}

