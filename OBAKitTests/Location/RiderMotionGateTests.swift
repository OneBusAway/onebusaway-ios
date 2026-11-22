//
//  RiderMotionGateTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct RiderMotionGateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Feeds one fix every `step` seconds from `from` up to and including `through`.
    private func feed(_ gate: inout RiderMotionGate, speed: Double, from: TimeInterval, through: TimeInterval, step: TimeInterval = 5, accuracy: Double = 1) {
        var offset = from
        while offset <= through {
            gate.record(speed: speed, speedAccuracy: accuracy, timestamp: start.addingTimeInterval(offset))
            offset += step
        }
    }

    @Test func `opens only after 30 seconds at bus speed`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 25)
        #expect(!gate.isMoving)
        feed(&gate, speed: 8, from: 30, through: 30)
        #expect(gate.isMoving)
    }

    @Test func `walking and jogging never open it`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 1.4, from: 0, through: 300)
        #expect(!gate.isMoving)
        feed(&gate, speed: 4, from: 305, through: 600)
        #expect(!gate.isMoving)
    }

    @Test func `a slow fix breaks the run`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 20)
        feed(&gate, speed: 3, from: 25, through: 25)
        feed(&gate, speed: 8, from: 30, through: 50)
        #expect(!gate.isMoving)
        feed(&gate, speed: 8, from: 55, through: 60)
        #expect(gate.isMoving)
    }

    @Test func `invalid speed says nothing and breaks a run`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 20)
        feed(&gate, speed: 8, from: 25, through: 25, accuracy: -1)
        feed(&gate, speed: 8, from: 30, through: 45)
        #expect(!gate.isMoving)

        feed(&gate, speed: 8, from: 50, through: 60)
        #expect(gate.isMoving)
        // Invalid fixes don't count as stopped either.
        feed(&gate, speed: -1, from: 65, through: 400, accuracy: -1)
        #expect(gate.isMoving)
    }

    @Test func `a red light keeps it open, a long stop closes it`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 30)
        #expect(gate.isMoving)

        feed(&gate, speed: 0, from: 35, through: 125)
        #expect(gate.isMoving)

        feed(&gate, speed: 8, from: 130, through: 140)
        feed(&gate, speed: 0, from: 145, through: 260)
        #expect(gate.isMoving)
        feed(&gate, speed: 0, from: 265, through: 265)
        #expect(!gate.isMoving)
    }

    @Test func `a long gap between fixes breaks the run`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 10)
        feed(&gate, speed: 8, from: 100, through: 125)
        #expect(!gate.isMoving)
    }

    @Test func `reset closes it`() {
        var gate = RiderMotionGate()
        feed(&gate, speed: 8, from: 0, through: 30)
        gate.reset()
        #expect(!gate.isMoving)
    }
}
