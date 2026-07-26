//
//  PromptCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKit

final class PromptCoordinatorTests: OBATestCase {

    private var clock: Date!

    override func setUp() async throws {
        try await super.setUp()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func makeCoordinator() -> PromptCoordinator {
        PromptCoordinator(userDefaults: userDefaults, now: { self.clock })
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
}
