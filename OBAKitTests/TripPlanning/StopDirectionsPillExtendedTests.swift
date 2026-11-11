//
//  StopDirectionsPillExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import OTPKit
@testable import OBAKit
@testable import OBAKitCore

/// Extended tests for `StopDirectionsPill` icon representations,
/// transportation mode mapping, formatting edge cases, and behavior equality.
@Suite(.serialized)
struct StopDirectionsPillExtendedTests {

    // MARK: - Transportation Mode Mapping

    @Test func `Pill maps to corresponding transport mode`() {
        #expect(StopDirectionsPill.walk.mode == .walk)
        #expect(StopDirectionsPill.bike.mode == .bike)
    }

    // MARK: - System Icons

    @Test func `Pill system images match platform convention`() {
        #expect(StopDirectionsPill.walk.systemImage == "figure.walk")
        #expect(StopDirectionsPill.bike.systemImage == "bicycle")
    }

    // MARK: - Text Formatting

    @Test func `Walk pill text formats duration accurately`() {
        let infoZero = WalkTimeInfo(walkMinutes: 0, distance: 0)
        let infoOne = WalkTimeInfo(walkMinutes: 1, distance: 80)
        let infoTen = WalkTimeInfo(walkMinutes: 10, distance: 800)

        #expect(StopDirectionsPill.walk.text(for: infoZero) == String(format: OBALoc("stop_page.walk_chip_minutes_fmt", value: "%d min walk", comment: ""), 0))
        #expect(StopDirectionsPill.walk.text(for: infoOne) == String(format: OBALoc("stop_page.walk_chip_minutes_fmt", value: "%d min walk", comment: ""), 1))
        #expect(StopDirectionsPill.walk.text(for: infoTen) == String(format: OBALoc("stop_page.walk_chip_minutes_fmt", value: "%d min walk", comment: ""), 10))
    }

    @Test func `Bike pill text formats duration accurately`() {
        let infoZero = WalkTimeInfo(walkMinutes: 0, distance: 0)
        let infoFive = WalkTimeInfo(walkMinutes: 5, distance: 1500)
        let infoThirty = WalkTimeInfo(walkMinutes: 30, distance: 9000)

        #expect(StopDirectionsPill.bike.text(for: infoZero) == String(format: OBALoc("stop_page.bike_chip_minutes_fmt", value: "%d min bike", comment: ""), 0))
        #expect(StopDirectionsPill.bike.text(for: infoFive) == String(format: OBALoc("stop_page.bike_chip_minutes_fmt", value: "%d min bike", comment: ""), 5))
        #expect(StopDirectionsPill.bike.text(for: infoThirty) == String(format: OBALoc("stop_page.bike_chip_minutes_fmt", value: "%d min bike", comment: ""), 30))
    }

    // MARK: - Behavior and Accessibility Hint Equality

    @Test func `Behavior equality matches on underlying variant`() {
        let walkBehavior1 = StopDirectionsPill.Behavior.askThenPlanTrip(.walk)
        let walkBehavior2 = StopDirectionsPill.Behavior.askThenPlanTrip(.walk)
        let bikeBehavior = StopDirectionsPill.Behavior.askThenPlanTrip(.bike)
        let mapsBehavior = StopDirectionsPill.Behavior.openMapsWalkingDirections

        #expect(walkBehavior1 == walkBehavior2)
        #expect(walkBehavior1 != bikeBehavior)
        #expect(walkBehavior1 != mapsBehavior)
        #expect(bikeBehavior != mapsBehavior)
    }

    @Test func `StopDirectionsPill promptTitle is non-empty localized text`() {
        #expect(!StopDirectionsPill.promptTitle.isEmpty)
    }

    @Test func `StopPillDirections none placeholder sets tripPlannerAvailable false`() {
        let none = StopPillDirections.none
        #expect(!none.tripPlannerAvailable)
    }
}
