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
// `Bundle` is already `@unchecked Sendable`; a subclass has to restate it or the
// compiler warns. Mutated only from the test that owns the instance.
private class PolicyBundle: Bundle, @unchecked Sendable {
    var config: [AnyHashable: Any] = [:]
    var version = "1.0"

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" { return config }
        if key == "CFBundleShortVersionString" { return version }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(enabled: Bool = true, version: String = "1.0", appStoreID: String? = "329380089") throws -> PolicyBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(PolicyBundle(path: dir.path))
        var config: [String: Any] = ["FeedbackPromptEnabled": enabled]
        if let appStoreID { config["AppStoreID"] = appStoreID }
        bundle.config = config
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

    /// `reset()` deliberately spares this key, so nothing else clears it between tests —
    /// and since it short-circuits `isPromptPending` to `true`, a leak turns later
    /// assertions into false passes.
    override func tearDown() async throws {
        userDefaults.removeObject(forKey: "ReviewPrompt.alwaysShow")
        try await super.tearDown()
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

    /// A fresh policy instance built from the same defaults (as after app
    /// termination) reads the persisted `successCount` and reports pending.
    ///
    /// NOTE: sharing the same `UserDefaults` suite means this alone doesn't
    /// distinguish "derived from `successCount`" from "a separately stored
    /// pending flag" — both would round-trip identically here. The genuine
    /// derived-not-stored pin is `test_negativeBacksOff180Days` and
    /// `test_abandonedAskBehavesAsDeferral`, which flip `isPromptPending`
    /// from `false` to `true` purely by advancing the clock with no
    /// intervening `recordSuccess()` call — no one-way edge-triggered flag
    /// could do that.
    func test_pendingSurvivesFreshPolicyInstance() {
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

        XCTAssertEqual(policy.outcome, .deferred, "outcome must be written up front, before the rider answers")
        XCTAssertFalse(policy.isPromptPending)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "backoff should still block")
    }

    /// Calling `recordOutcome` without a preceding `recordPromptPresented()` is an
    /// undefended ordering hole: with no `lastAskedDate` on file, the backoff
    /// `if let` in `isPromptPending` would be skipped entirely, and `successCount`
    /// was never zeroed — so the rider would stay pending and get re-prompted on
    /// every subsequent stop view, unboundedly, without ever burning an ask.
    func test_outcomeWithoutPresentationStillConsumesTheAsk() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        // No recordPromptPresented() call.
        policy.recordOutcome(.negative)

        XCTAssertFalse(policy.isPromptPending, "recording an outcome must always consume the ask")
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

        // Day 59 with the success bar already cleared: only the backoff can still be
        // holding the prompt back. Without this half the test passes for any backoff
        // shorter than 61 days, because the day-61 assertion below is gated on the
        // success count rather than on elapsed time.
        advance(days: 59)
        recordSuccesses(5, on: policy)
        XCTAssertFalse(policy.isPromptPending, "the 60-day deferral must still be closed on day 59")

        advance(days: 2)
        XCTAssertTrue(policy.isPromptPending, "and open once it elapses")
    }

    /// A white-label target with no `AppStoreID` can't send anyone to the App Store, so
    /// it must never be asked. Shipping without this gate meant KiedyBus riders got the
    /// prompt, tapped "Yes!", went nowhere, and were recorded `.positive` — permanently
    /// silencing both branches for someone who was never really asked.
    func test_missingAppStoreIDSuppressesThePromptEntirely() throws {
        bundle = try PolicyBundle.create(appStoreID: nil)
        let policy = makePolicy()
        recordSuccesses(5, on: policy)

        XCTAssertFalse(policy.isPromptPending)

        // Not even the debug override may open it — there is still nowhere to go.
        policy.alwaysShowPrompt = true
        XCTAssertFalse(policy.isPromptPending)
    }

    /// The Settings footer promises the toggle survives a reset.
    func test_resetPreservesTheDebugOverride() {
        let policy = makePolicy()
        policy.alwaysShowPrompt = true
        recordSuccesses(5, on: policy)

        policy.reset()

        XCTAssertTrue(policy.alwaysShowPrompt)
        XCTAssertEqual(policy.successCount, 0)
    }

    /// A QA tap on "Yes!" must not write `.positive`. `recordPromptPresented()` already
    /// skips the two permanent gates under the toggle so a QA pass can't silence the
    /// organic prompt for good — but `.positive` is itself permanent, so letting it
    /// through the debug path would defeat exactly that protection.
    ///
    /// The install is still left in the ordinary `.deferred` state the presentation
    /// writes up front, so the organic prompt comes back on its own after the 60-day
    /// backoff rather than never.
    func test_debugOverrideDoesNotRecordOutcomes() {
        let policy = makePolicy()
        recordSuccesses(5, on: policy)
        policy.alwaysShowPrompt = true

        policy.recordPromptPresented()
        policy.recordOutcome(.positive)

        XCTAssertEqual(policy.outcome, .deferred, "the QA answer must not be persisted")

        policy.alwaysShowPrompt = false
        advance(days: 61)
        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending, "a QA pass defers the organic prompt, it doesn't kill it")
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

    /// `alwaysShowPrompt` short-circuits `isPromptPending` ahead of the ask cap and the
    /// version gate, so presentations made under it must not spend either. Three QA taps
    /// used to silence the organic prompt on that install for good.
    func test_alwaysShowDoesNotSpendTheLifetimeAskBudget() {
        let policy = makePolicy()
        policy.alwaysShowPrompt = true

        for _ in 0..<5 {
            policy.recordPromptPresented()
            policy.recordOutcome(.deferred)
        }

        policy.alwaysShowPrompt = false
        advance(days: 61)
        recordSuccesses(5, on: policy)
        XCTAssertTrue(policy.isPromptPending, "the real prompt is still available after five debug asks")
    }

    /// Everything else about `recordPromptPresented()` still runs under the toggle, so an
    /// abandoned debug alert lands in the same defined state a real one would.
    func test_alwaysShowStillWritesTheDeferredOutcomeUpFront() {
        let policy = makePolicy()
        policy.alwaysShowPrompt = true
        recordSuccesses(5, on: policy)

        policy.recordPromptPresented()

        XCTAssertEqual(policy.outcome, .deferred)
        XCTAssertEqual(policy.successCount, 0)
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

/// The write-review URL is the entire point of the positive branch, and it fails
/// silently when wrong — drop `?action=write-review` and the App Store opens the
/// ordinary product page, so the rider lands somewhere plausible and never reviews.
final class WriteReviewURLTests: XCTestCase {

    @MainActor
    func test_writeReviewURL_carriesTheWriteReviewAction() throws {
        let url = try XCTUnwrap(FeedbackPromptPresenter.writeReviewURL(appStoreID: "329380089"))
        XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id329380089?action=write-review")
    }
}
