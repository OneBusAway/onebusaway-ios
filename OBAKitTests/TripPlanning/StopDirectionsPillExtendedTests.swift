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
        let infoZero = WalkTimeInfo(walkDistanceMeters: 0, walkMinutes: 0)
        let infoOne = WalkTimeInfo(walkDistanceMeters: 80, walkMinutes: 1)
        let infoTen = WalkTimeInfo(walkDistanceMeters: 800, walkMinutes: 10)

        #expect(StopDirectionsPill.walk.text(for: infoZero).contains("0 min walk"))
        #expect(StopDirectionsPill.walk.text(for: infoOne).contains("1 min walk"))
        #expect(StopDirectionsPill.walk.text(for: infoTen).contains("10 min walk"))
    }

    @Test func `Bike pill text formats duration accurately`() {
        let infoZero = WalkTimeInfo(walkDistanceMeters: 0, walkMinutes: 0)
        let infoFive = WalkTimeInfo(walkDistanceMeters: 1500, walkMinutes: 5)
        let infoThirty = WalkTimeInfo(walkDistanceMeters: 9000, walkMinutes: 30)

        #expect(StopDirectionsPill.bike.text(for: infoZero).contains("0 min bike"))
        #expect(StopDirectionsPill.bike.text(for: infoFive).contains("5 min bike"))
        #expect(StopDirectionsPill.bike.text(for: infoThirty).contains("30 min bike"))
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
