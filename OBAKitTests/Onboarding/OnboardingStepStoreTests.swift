//
//  OnboardingStepStoreTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit

@MainActor
final class OnboardingStepStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: OnboardingStepStore!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        let name = "OnboardingStepStoreTests-\(UUID().uuidString)"
        await MainActor.run {
            suiteName = name
            userDefaults = UserDefaults(suiteName: name)
            store = OnboardingStepStore(userDefaults: userDefaults)
        }
    }

    override func tearDown() async throws {
        let name = await MainActor.run { suiteName }
        UserDefaults().removePersistentDomain(forName: name!)
        try await super.tearDown()
    }

    func test_unseenStep_hasVersionZero() {
        XCTAssertEqual(store.seenVersion(of: .notifications), 0)
        XCTAssertTrue(store.isEmpty)
    }

    func test_markSeen_roundTripsThroughUserDefaults() {
        store.markSeen(.welcome, version: 1)
        XCTAssertEqual(store.seenVersion(of: .welcome), 1)
        XCTAssertFalse(store.isEmpty)

        // A second store over the same defaults sees the same data.
        let rehydrated = OnboardingStepStore(userDefaults: userDefaults)
        XCTAssertEqual(rehydrated.seenVersion(of: .welcome), 1)
    }

    func test_markSeen_neverLowersVersion() {
        store.markSeen(.location, version: 3)
        store.markSeen(.location, version: 1)
        XCTAssertEqual(store.seenVersion(of: .location), 3)
    }

    func test_backfill_existingUser_marksLegacyStepsButNotNotifications() {
        XCTAssertTrue(store.backfillIfNeeded(hasCurrentRegion: true))
        XCTAssertEqual(store.seenVersion(of: .welcome), 1)
        XCTAssertEqual(store.seenVersion(of: .location), 1)
        XCTAssertEqual(store.seenVersion(of: .region), 1)
        XCTAssertEqual(store.seenVersion(of: .done), 1)
        XCTAssertEqual(store.seenVersion(of: .notifications), 0)
        XCTAssertEqual(store.seenVersion(of: .migration), 0)
    }

    func test_backfill_newUser_doesNothing() {
        XCTAssertFalse(store.backfillIfNeeded(hasCurrentRegion: false))
        XCTAssertTrue(store.isEmpty)
    }

    func test_backfill_nonEmptyStore_neverRunsAgain() {
        store.markSeen(.welcome, version: 1)
        XCTAssertFalse(store.backfillIfNeeded(hasCurrentRegion: true))
        XCTAssertEqual(store.seenVersion(of: .region), 0)
    }
}
