//
//  PromptCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import UIKit
@testable import OBAKit

final class PromptCoordinatorTests: OBATestCase {

    private var clock: Date!

    override func setUp() async throws {
        try await super.setUp()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    /// Defaults to a private center, not `.default`: every coordinator registers a
    /// `willEnterForeground` observer, and a real foreground event mid-run would silently
    /// reset the session out from under a session-state assertion.
    private func makeCoordinator(notificationCenter: NotificationCenter = NotificationCenter()) -> PromptCoordinator {
        PromptCoordinator(userDefaults: userDefaults, notificationCenter: notificationCenter, now: { self.clock })
    }

    private func advance(days: Int) {
        clock = clock.addingTimeInterval(TimeInterval(days) * 86400)
    }

    // MARK: - One interruption per session

    func test_reviewAllowedInFreshSession() {
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    func test_reviewRefusedAfterSurveyPromptSameSession() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)
        XCTAssertFalse(coordinator.canShowReviewPrompt())
    }

    /// The headline case: the session budget has to hold against the review prompt
    /// itself, not just against the other two kinds.
    func test_reviewRefusedAfterReviewPromptSameSession() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        XCTAssertFalse(coordinator.canShowReviewPrompt())
    }

    func test_reviewRefusedAfterDonationModalSameSession() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        XCTAssertFalse(coordinator.canShowReviewPrompt())
    }

    func test_newSessionClearsSessionState() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        coordinator.sawErrorThisSession = true
        XCTAssertFalse(coordinator.canShowInlineCards())

        coordinator.beginNewSession()
        XCTAssertTrue(coordinator.canShowInlineCards())
        XCTAssertFalse(coordinator.sawErrorThisSession)
    }

    func test_noteNotShownReleasesTheSessionSlot() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)
        XCTAssertFalse(coordinator.canShowReviewPrompt())

        coordinator.noteNotShown(.surveyPrompt)
        XCTAssertTrue(coordinator.canShowReviewPrompt())
    }

    // MARK: - Error suppression

    func test_reviewRefusedAfterStopLoadError() {
        let coordinator = makeCoordinator()
        coordinator.sawErrorThisSession = true
        XCTAssertFalse(coordinator.canShowReviewPrompt())
    }

    // MARK: - 14-day engagement cooldown

    func test_reviewRefusedWithin14DaysOfDonationModal() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)

        advance(days: 13)
        let next = makeCoordinator()
        XCTAssertFalse(next.canShowReviewPrompt())

        advance(days: 2)
        let later = makeCoordinator()
        XCTAssertTrue(later.canShowReviewPrompt())
    }

    func test_reviewRefusedWithin14DaysOfSurveyEngagement() {
        let coordinator = makeCoordinator()
        coordinator.noteSurveyEngaged()

        advance(days: 13)
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    /// A review prompt is not itself a donation/survey engagement, so it must
    /// not start the 14-day clock that gates *itself*.
    func test_reviewPromptDoesNotStartEngagementCooldown() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)

        let nextSession = makeCoordinator()
        XCTAssertTrue(nextSession.canShowReviewPrompt())
    }

    // MARK: - Inline cards

    func test_inlineCardsAllowedByDefault() {
        XCTAssertTrue(makeCoordinator().canShowInlineCards())
    }

    func test_inlineCardsSuppressedForRestOfSessionAfterReview() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        XCTAssertFalse(coordinator.canShowInlineCards())
    }

    /// Regression test for the starvation bug: rendering an inline donation
    /// card is not an interruption and must never consume the review budget,
    /// no matter how many times it happens.
    func test_inlineCardRendersNeverAffectReviewEligibility() {
        let coordinator = makeCoordinator()
        for _ in 0..<100 {
            _ = coordinator.canShowInlineCards()
        }
        XCTAssertTrue(coordinator.canShowReviewPrompt())
    }

    // MARK: - Reset

    func test_resetClearsEngagementCooldown() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        coordinator.reset()

        let next = makeCoordinator()
        XCTAssertTrue(next.canShowReviewPrompt())
    }

    // MARK: - noteNotShown undo safety (review-round Finding 1 / 3a)

    /// A genuine `noteSurveyEngaged()` that happens between a `noteShown(_:)`
    /// gate and its matching `noteNotShown(_:)` must survive: the undo must
    /// only ever roll back its own write, never a later engagement that
    /// happens to share the same persisted key.
    func test_noteNotShownDoesNotClobberLaterSurveyEngagement() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)

        clock = clock.addingTimeInterval(1)
        coordinator.noteSurveyEngaged()

        coordinator.noteNotShown(.surveyPrompt)

        advance(days: 13)
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    /// Shows `.donationModal` then, 5 days later, `.surveyPrompt`; only the
    /// most recent `noteShown(_:)` has a live undo record, so releasing the
    /// *earlier* kind's slot must decline to touch the engagement date at
    /// all — it must not revert the cooldown to the earlier (more expired)
    /// date. The two check points are chosen so that "correctly kept the
    /// surveyPrompt date" and "wrongly reverted to the donationModal date"
    /// disagree: at day 15 only the wrong-revert behavior would have let the
    /// cooldown lapse.
    func test_noteNotShownForEarlierKindDoesNotRestoreAfterNewerKindShown() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal) // T0

        advance(days: 5)
        coordinator.noteShown(.surveyPrompt) // T0 + 5d
        coordinator.noteNotShown(.donationModal) // mismatched kind — must be a no-op

        advance(days: 10) // now = T0 + 15d: within 14d of surveyPrompt's date, past donationModal's
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 5) // now = T0 + 20d: past both 14-day windows
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    /// Same as above with the two kinds reversed, to pin that the "decline to
    /// restore" behavior isn't an artifact of which kind happens to be shown
    /// second.
    func test_noteNotShownForEarlierKindDoesNotRestoreAfterNewerKindShownReversed() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt) // T0

        advance(days: 5)
        coordinator.noteShown(.donationModal) // T0 + 5d
        coordinator.noteNotShown(.surveyPrompt) // mismatched kind — must be a no-op

        advance(days: 10) // now = T0 + 15d
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 5) // now = T0 + 20d
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    /// Two kinds gated at once, both rolled back: neither was ever presented, so no
    /// cooldown may survive.
    ///
    /// With a single undo slot the second `noteShown` evicted the first one's record,
    /// and the first's `noteNotShown` then found nothing to restore — leaving the
    /// engagement date set, and the review prompt blocked for 14 days, on behalf of two
    /// prompts the rider never saw.
    func test_bothKindsRolledBackLeaveNoCooldown() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt) // T0

        advance(days: 1)
        coordinator.noteShown(.donationModal) // T0 + 1d

        advance(days: 1)
        coordinator.noteNotShown(.donationModal) // restores the survey's date
        coordinator.noteNotShown(.surveyPrompt) // must clear it entirely

        XCTAssertTrue(makeCoordinator().canShowReviewPrompt(), "no engagement ever happened")
    }

    /// `noteNotShown(_:)` with no preceding `noteShown(_:)` for that kind must
    /// be a safe no-op rather than disturbing an unrelated, already-persisted
    /// engagement (e.g. one written directly by `noteSurveyEngaged()`).
    func test_noteNotShownWithoutMatchingNoteShownIsANoOp() {
        let coordinator = makeCoordinator()
        coordinator.noteSurveyEngaged()
        coordinator.noteNotShown(.surveyPrompt)

        advance(days: 13)
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    /// A `noteNotShown(_:)` call that arrives after `beginNewSession()` has
    /// already rolled the session over must not resurrect the discarded undo
    /// record and erase the engagement the earlier `noteShown(_:)` recorded.
    func test_noteNotShownAfterNewSessionDoesNotRestoreStaleEngagement() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        coordinator.beginNewSession()

        coordinator.noteNotShown(.donationModal)

        advance(days: 13)
        XCTAssertFalse(makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        XCTAssertTrue(makeCoordinator().canShowReviewPrompt())
    }

    // MARK: - Foreground notification wiring (review-round Finding 2 / 3b)

    /// Exercises the actual `NotificationCenter` observer path end to end:
    /// posting `willEnterForegroundNotification` on an injected center must
    /// clear session state, proving `init` and `deinit` operate on the same
    /// (injected, not `.default`) center.
    func test_foregroundNotificationBeginsNewSession() {
        let center = NotificationCenter()
        let coordinator = makeCoordinator(notificationCenter: center)
        coordinator.noteShown(.review)
        coordinator.sawErrorThisSession = true
        XCTAssertFalse(coordinator.canShowInlineCards())

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // The observer block was registered on the main OperationQueue, which
        // dispatches asynchronously; round-trip through the main queue once
        // more so it has run before we assert.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)

        XCTAssertTrue(coordinator.canShowInlineCards())
        XCTAssertFalse(coordinator.sawErrorThisSession)
    }
}
