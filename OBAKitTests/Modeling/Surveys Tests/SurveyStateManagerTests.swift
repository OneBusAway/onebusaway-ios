//
//  SurveyStateManagerTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 13/12/2025.
//

import XCTest
import Nimble

final class SurveyStateManagerTests: OBATestCase {

    func test_shouldShowSurvey_returnsFalse_whenFeatureDisabled() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(3)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: false))

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenAppLaunchIsZero() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(0)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: true))

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenLaunchCountReminderNotZero() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(4)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: true))

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenLaunchCountReminderIsZero() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(6)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: true))

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beTrue())
    }

    func test_shouldShowSurvey_returnsFalse_whenNextReminderDateIsInFuture() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(6)
        surveyStore.setSurveyPreferences(
            .init(
                isSurveyEnabled: true,
                nextReminderDate:  Date().addingTimeInterval(3600)
            )
        )

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenNextReminderDateIsInPast() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(6)
        surveyStore.setSurveyPreferences(
            .init(
                isSurveyEnabled: true,
                nextReminderDate:  Date().addingTimeInterval(-300)
            )
        )

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beTrue())
    }

    func test_shouldShowSurvey_returnsTrue_whenReminderDateIsNil() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(6)
        surveyStore.setSurveyPreferences(
            .init(
                isSurveyEnabled: true,
                nextReminderDate: nil
            )
        )

        let state = surveyStateManager.shouldShowSurvey()
        expect(state).to(beTrue())
    }

    func test_setNextReminderDate_setsDateThreeDaysAhead() {
        let now = Date()

        surveyStateManager.setNextReminderDate()

        let storedDate = surveyStateManager.surveyStore.surveyPreferences().nextReminderDate
        expect(storedDate).toNot(beNil())

        let diff = Calendar.current.dateComponents([.day], from: now, to: storedDate!).day
        expect(diff).to(equal(3))
    }

    func test_setNextReminderDate_overwritesExistingReminderDate() {
        surveyStateManager.surveyStore.setSurveyPreferences(.init(nextReminderDate: Date().addingTimeInterval(-50)))

        surveyStateManager.setNextReminderDate()

        let newDate = surveyStateManager.surveyStore.surveyPreferences().nextReminderDate
        expect(newDate).toNot(beNil())
        expect(newDate).to(beGreaterThan(Date()))
    }

    func test_setSurveySkipped_appendsNewID() {
        surveyStateManager.setSurveySkipped(7)

        let skippedIDs = surveyStateManager.surveyStore.skippedSurveys
        expect(skippedIDs).to(equal([7]))
    }

    func test_setSurveySkipped_doesNotModifyCompletedSurveys() {
        surveyStateManager.surveyStore.setSurveyPreferences(.init(completedSurveyIDs: [8]))

        surveyStateManager.setSurveySkipped(9)
        let completedIDs = surveyStateManager.surveyStore.completedSurveys
        expect(completedIDs).to(equal([8]))
    }

    // MARK: - Combined Behavior Tests

    func test_completingThenSkipping_storesCorrectly() {
        surveyStateManager.setSurveyCompleted(1)
        surveyStateManager.setSurveySkipped(2)

        expect(self.surveyStateManager.surveyStore.completedSurveys).to(equal([1]))
        expect(self.surveyStateManager.surveyStore.skippedSurveys).to(equal([2]))
    }

    func test_shouldShowSurvey_whenLaunchIsThirdButFeatureDisabled_returnsFalse() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(3)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: false))

        expect(self.surveyStateManager.shouldShowSurvey()).to(beFalse())
    }

    func test_shouldShowSurvey_minimumValidCase() {
        let surveyStore = surveyStateManager.surveyStore as! SurveyPreferencesStoreMock
        surveyStore.setAppLaunchCount(3)
        surveyStore.setSurveyPreferences(.init(isSurveyEnabled: true))

        expect(self.surveyStateManager.shouldShowSurvey()).to(beTrue())
    }
}
