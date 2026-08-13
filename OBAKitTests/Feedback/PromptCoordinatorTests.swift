//
//  PromptCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit

@Suite(.serialized)
final class PromptCoordinatorTests: OBATestCase {

    private var clock: Date!

    override init() async throws {
        try await super.init()

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

    @Test func `Review allowed in fresh session`() {
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    @Test func `Review refused after survey prompt same session`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)
        #expect(!coordinator.canShowReviewPrompt())
    }

    /// The headline case: the session budget has to hold against the review prompt
    /// itself, not just against the other two kinds.
    @Test func `Review refused after review prompt same session`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        #expect(!coordinator.canShowReviewPrompt())
    }

    @Test func `Review refused after donation modal same session`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        #expect(!coordinator.canShowReviewPrompt())
    }

    @Test func `New session clears session state`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        coordinator.sawErrorThisSession = true
        #expect(!coordinator.canShowInlineCards())

        coordinator.beginNewSession()
        #expect(coordinator.canShowInlineCards())
        #expect(!coordinator.sawErrorThisSession)
    }

    @Test func `Note not shown releases the session slot`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)
        #expect(!coordinator.canShowReviewPrompt())

        coordinator.noteNotShown(.surveyPrompt)
        #expect(coordinator.canShowReviewPrompt())
    }

    // MARK: - Error suppression

    @Test func `Review refused after stop load error`() {
        let coordinator = makeCoordinator()
        coordinator.sawErrorThisSession = true
        #expect(!coordinator.canShowReviewPrompt())
    }

    // MARK: - 14-day engagement cooldown

    @Test func `Review refused within 14 days of donation modal`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)

        advance(days: 13)
        let next = makeCoordinator()
        #expect(!next.canShowReviewPrompt())

        advance(days: 2)
        let later = makeCoordinator()
        #expect(later.canShowReviewPrompt())
    }

    @Test func `Review refused within 14 days of survey engagement`() {
        let coordinator = makeCoordinator()
        coordinator.noteSurveyEngaged()

        advance(days: 13)
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    /// A review prompt is not itself a donation/survey engagement, so it must
    /// not start the 14-day clock that gates *itself*.
    @Test func `Review prompt does not start engagement cooldown`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)

        let nextSession = makeCoordinator()
        #expect(nextSession.canShowReviewPrompt())
    }

    // MARK: - Inline cards

    @Test func `Inline cards allowed by default`() {
        #expect(makeCoordinator().canShowInlineCards())
    }

    @Test func `Inline cards suppressed for rest of session after review`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.review)
        #expect(!coordinator.canShowInlineCards())
    }

    /// Regression test for the starvation bug: rendering an inline donation
    /// card is not an interruption and must never consume the review budget,
    /// no matter how many times it happens.
    @Test func `Inline card renders never affect review eligibility`() {
        let coordinator = makeCoordinator()
        for _ in 0..<100 {
            _ = coordinator.canShowInlineCards()
        }
        #expect(coordinator.canShowReviewPrompt())
    }

    // MARK: - Reset

    @Test func `Reset clears engagement cooldown`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        coordinator.reset()

        let next = makeCoordinator()
        #expect(next.canShowReviewPrompt())
    }

    // MARK: - noteNotShown undo safety (review-round Finding 1 / 3a)

    /// A genuine `noteSurveyEngaged()` that happens between a `noteShown(_:)`
    /// gate and its matching `noteNotShown(_:)` must survive: the undo must
    /// only ever roll back its own write, never a later engagement that
    /// happens to share the same persisted key.
    @Test func `Note not shown does not clobber later survey engagement`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt)

        clock = clock.addingTimeInterval(1)
        coordinator.noteSurveyEngaged()

        coordinator.noteNotShown(.surveyPrompt)

        advance(days: 13)
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    /// Shows `.donationModal` then, 5 days later, `.surveyPrompt`; only the
    /// most recent `noteShown(_:)` has a live undo record, so releasing the
    /// *earlier* kind's slot must decline to touch the engagement date at
    /// all — it must not revert the cooldown to the earlier (more expired)
    /// date. The two check points are chosen so that "correctly kept the
    /// surveyPrompt date" and "wrongly reverted to the donationModal date"
    /// disagree: at day 15 only the wrong-revert behavior would have let the
    /// cooldown lapse.
    @Test func `Note not shown for earlier kind does not restore after newer kind shown`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal) // T0

        advance(days: 5)
        coordinator.noteShown(.surveyPrompt) // T0 + 5d
        coordinator.noteNotShown(.donationModal) // mismatched kind — must be a no-op

        advance(days: 10) // now = T0 + 15d: within 14d of surveyPrompt's date, past donationModal's
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 5) // now = T0 + 20d: past both 14-day windows
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    /// Same as above with the two kinds reversed, to pin that the "decline to
    /// restore" behavior isn't an artifact of which kind happens to be shown
    /// second.
    @Test func `Note not shown for earlier kind does not restore after newer kind shown reversed`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt) // T0

        advance(days: 5)
        coordinator.noteShown(.donationModal) // T0 + 5d
        coordinator.noteNotShown(.surveyPrompt) // mismatched kind — must be a no-op

        advance(days: 10) // now = T0 + 15d
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 5) // now = T0 + 20d
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    /// Two kinds gated at once, both rolled back: neither was ever presented, so no
    /// cooldown may survive.
    ///
    /// With a single undo slot the second `noteShown` evicted the first one's record,
    /// and the first's `noteNotShown` then found nothing to restore — leaving the
    /// engagement date set, and the review prompt blocked for 14 days, on behalf of two
    /// prompts the rider never saw.
    @Test func `Both kinds rolled back leave no cooldown`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.surveyPrompt) // T0

        advance(days: 1)
        coordinator.noteShown(.donationModal) // T0 + 1d

        advance(days: 1)
        coordinator.noteNotShown(.donationModal) // restores the survey's date
        coordinator.noteNotShown(.surveyPrompt) // must clear it entirely

        #expect(makeCoordinator().canShowReviewPrompt(), "no engagement ever happened")
    }

    /// `noteNotShown(_:)` with no preceding `noteShown(_:)` for that kind must
    /// be a safe no-op rather than disturbing an unrelated, already-persisted
    /// engagement (e.g. one written directly by `noteSurveyEngaged()`).
    @Test func `Note not shown without matching note shown is a no op`() {
        let coordinator = makeCoordinator()
        coordinator.noteSurveyEngaged()
        coordinator.noteNotShown(.surveyPrompt)

        advance(days: 13)
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    /// A `noteNotShown(_:)` call that arrives after `beginNewSession()` has
    /// already rolled the session over must not resurrect the discarded undo
    /// record and erase the engagement the earlier `noteShown(_:)` recorded.
    @Test func `Note not shown after new session does not restore stale engagement`() {
        let coordinator = makeCoordinator()
        coordinator.noteShown(.donationModal)
        coordinator.beginNewSession()

        coordinator.noteNotShown(.donationModal)

        advance(days: 13)
        #expect(!makeCoordinator().canShowReviewPrompt())

        advance(days: 2)
        #expect(makeCoordinator().canShowReviewPrompt())
    }

    // MARK: - Foreground notification wiring (review-round Finding 2 / 3b)

    /// Exercises the actual `NotificationCenter` observer path end to end:
    /// posting `willEnterForegroundNotification` on an injected center must
    /// clear session state, proving `init` and `deinit` operate on the same
    /// (injected, not `.default`) center.
    @Test func `Foreground notification begins new session`() async {
        let center = NotificationCenter()
        let coordinator = makeCoordinator(notificationCenter: center)
        coordinator.noteShown(.review)
        coordinator.sawErrorThisSession = true
        #expect(!coordinator.canShowInlineCards())

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // The observer block was registered on the main OperationQueue, which
        // dispatches asynchronously; round-trip through the main queue once
        // more so it has run before we assert.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        #expect(coordinator.canShowInlineCards())
        #expect(!coordinator.sawErrorThisSession)
    }
}
