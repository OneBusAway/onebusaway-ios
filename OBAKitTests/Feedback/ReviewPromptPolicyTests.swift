//
//  ReviewPromptPolicyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit
@testable import OBAKitCore

/// A `Bundle` reporting a configurable `OBAKitConfig`, so the policy's kill
/// switch and version gate are testable without the host app's Info.plist.
private class PolicyBundle: Bundle {
    var config: [AnyHashable: Any] = [:]
    var version = "1.0"

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" { return config }
        if key == "CFBundleShortVersionString" { return version }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(enabled: Bool = true, version: String = "1.0") throws -> PolicyBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(PolicyBundle(path: dir.path))
        bundle.config = ["FeedbackPromptEnabled": enabled]
        bundle.version = version
        return bundle
    }
}

final class ReviewPromptPolicyTests: OBATestCase {

    private var clock: Date!
    private var bundle: PolicyBundle!

    override func setUp() async throws {
        try await super.setUp()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        bundle = try PolicyBundle.create()
    }

    private func makePolicy() -> ReviewPromptPolicy {
        ReviewPromptPolicy(userDefaults: userDefaults, bundle: bundle, now: { self.clock })
    }

    private func advance(days: Int) {
        clock = clock.addingTimeInterval(TimeInterval(days) * 86400)
    }

    private func recordSuccesses(_ count: Int, on policy: ReviewPromptPolicy) {
        for _ in 0..<count { policy.recordSuccess() }
    }

    // MARK: - Threshold

    func test_fourSuccesses_isNotPending() {
        let policy = makePolicy()
        recordSuccesses(4, on: policy)
        XCTAssertFalse(policy.isPromptPending)
    }

    func test_fiveSuccesses_isPending() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending)
    }

    /// The derived-not-stored requirement: a policy rebuilt from the same
    /// defaults (as after app termination) must still report pending.
    func test_pendingSurvivesRelaunchPastThreshold() {
        let first = makePolicy()
        recordSuccesses(7, on: first)
        XCTAssertTrue(first.isPromptPending)

        let second = makePolicy()
        XCTAssertTrue(second.isPromptPending)
    }

    // MARK: - Presentation bookkeeping

    func test_presentingResetsCounterAndSetsDeferredOutcome() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()

        XCTAssertFalse(policy.isPromptPending)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "backoff should still block")
    }

    /// An alert the rider abandons (app killed mid-prompt) never gets an
    /// outcome written, so it must already be a well-defined deferral.
    func test_abandonedAskBehavesAsDeferral() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        // No recordOutcome call — simulate abandonment.

        bundle.version = "1.1"
        advance(days: 59)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "59 days is inside the 60-day deferral")

        advance(days: 2)
        XCTAssertTrue(policy.isPromptPending)
    }

    // MARK: - Outcomes

    func test_positiveSilencesPermanently() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.positive)

        bundle.version = "2.0"
        advance(days: 3650)
        recordSuccesses(50, on: policy)
        XCTAssertFalse(policy.isPromptPending)
    }

    func test_negativeBacksOff180Days() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.negative)

        bundle.version = "1.1"
        advance(days: 179)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending)

        advance(days: 2)
        XCTAssertTrue(policy.isPromptPending)
    }

    func test_deferredBacksOff60Days() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.deferred)

        bundle.version = "1.1"
        advance(days: 61)
        XCTAssertFalse(policy.isPromptPending, "time alone must not re-arm the prompt")

        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending)
    }

    // MARK: - Version gate

    func test_sameVersionBlocksSecondPrompt() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.deferred)

        advance(days: 61)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "same app version must not re-prompt")

        bundle.version = "1.1"
        XCTAssertTrue(policy.isPromptPending)
    }

    // MARK: - Lifetime cap

    func test_thirdAskSilencesPermanently() {
        let policy = makePolicy()
        let versions = ["1.1", "1.2", "1.3"]

        for (index, version) in versions.enumerated() {
            recordSuccesses(5, on: policy)
            XCTAssertTrue(policy.isPromptPending, "ask \(index + 1) should be pending")
            policy.recordPromptPresented()
            policy.recordOutcome(.deferred)
            bundle.version = version
            advance(days: 61)
        }

        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "askCount reached 3")
    }

    /// The cap counts asks, not deferrals, so a mixed sequence still caps.
    func test_capCountsAsksRegardlessOfOutcome() {
        let policy = makePolicy()

        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.deferred)
        bundle.version = "1.1"
        advance(days: 61)

        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.negative)
        bundle.version = "1.2"
        advance(days: 181)

        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending, "third ask still allowed")
        policy.recordPromptPresented()
        policy.recordOutcome(.deferred)
        bundle.version = "1.3"
        advance(days: 61)

        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending)
    }

    // MARK: - Kill switch and debug

    func test_disabledBundleIsNeverPending() throws {
        bundle = try PolicyBundle.create(enabled: false)
        let policy = makePolicy()
        recordSuccesses(20, on: policy)
        XCTAssertFalse(policy.isPromptPending)
    }

    func test_alwaysShowBypassesGatesButNotKillSwitch() throws {
        let policy = makePolicy()
        policy.alwaysShowPrompt = true
        XCTAssertTrue(policy.isPromptPending, "no successes recorded, but debug override is on")

        bundle = try PolicyBundle.create(enabled: false)
        let disabled = makePolicy()
        disabled.alwaysShowPrompt = true
        XCTAssertFalse(disabled.isPromptPending)
    }

    func test_resetClearsAllState() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.recordPromptPresented()
        policy.recordOutcome(.positive)
        XCTAssertFalse(policy.isPromptPending)

        policy.reset()
        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending)
    }
}
