//
//  SurveyServiceStateTests.swift
//  OBAKitTests
//
//  Created by Mohamed Sliem on 13/12/2025.
//

import XCTest
import Nimble
@testable import OBAKitCore

@MainActor
final class SurveyServiceStateTests: OBATestCase {

    nonisolated(unsafe) private var surveyService: SurveyService!
    nonisolated(unsafe) private var testUserDefaults: UserDefaults!
    nonisolated(unsafe) private var testUserDataStore: UserDefaultsStore!

    override func setUp() {
        super.setUp()
        testUserDefaults = buildUserDefaults(suiteName: "\(userDefaultsSuiteName).state")
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).state")
        testUserDataStore = UserDefaultsStore(userDefaults: testUserDefaults)
        surveyService = SurveyService(apiService: nil, userDataStore: testUserDataStore)
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "\(userDefaultsSuiteName).state")
        super.tearDown()
    }

    // MARK: - shouldShowSurvey

    func test_shouldShowSurvey_returnsFalse_whenFeatureDisabled() {
        testUserDataStore.isSurveyEnabled = false
        // Even with correct launch count, disabled means no survey
        setAppLaunchCount(3)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenAppLaunchIsZero() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(0)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsFalse_whenLaunchCountNotMultipleOfThree() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(4)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenLaunchCountIsMultipleOfThree() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    func test_shouldShowSurvey_returnsFalse_whenNextReminderDateIsInFuture() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(3600)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beFalse())
    }

    func test_shouldShowSurvey_returnsTrue_whenNextReminderDateIsInPast() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(-300)

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    func test_shouldShowSurvey_returnsTrue_whenReminderDateIsNil() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(6)
        testUserDataStore.nextSurveyReminderDate = nil

        let result = surveyService.shouldShowSurvey()
        expect(result).to(beTrue())
    }

    // MARK: - setNextReminderDate

    func test_setNextReminderDate_setsDateThreeDaysAhead() {
        let now = Date()

        surveyService.setNextReminderDate()

        let storedDate = testUserDataStore.nextSurveyReminderDate
        expect(storedDate).toNot(beNil())

        let diff = Calendar.current.dateComponents([.day], from: now, to: storedDate!).day
        expect(diff).to(equal(3))
    }

    func test_setNextReminderDate_overwritesExistingDate() {
        testUserDataStore.nextSurveyReminderDate = Date().addingTimeInterval(-50)

        surveyService.setNextReminderDate()

        let newDate = testUserDataStore.nextSurveyReminderDate
        expect(newDate).toNot(beNil())
        expect(newDate).to(beGreaterThan(Date()))
    }

    // MARK: - markSurveyCompleted

    func test_markSurveyCompleted_tracksSurvey() {
        let survey = makeSurvey(id: 7)
        surveyService.markSurveyCompleted(survey)

        let userID = testUserDataStore.surveyUserIdentifier
        expect(self.testUserDataStore.isSurveyCompleted(surveyId: 7, userIdentifier: userID)).to(beTrue())
    }

    // MARK: - markSurveyForLater

    func test_markSurveyForLater_tracksSurvey() {
        let survey = makeSurvey(id: 9)
        surveyService.markSurveyForLater(survey)

        let userID = testUserDataStore.surveyUserIdentifier
        // Immediately after marking, shouldShowSurveyLater returns false (0 launches since marking)
        expect(self.testUserDataStore.shouldShowSurveyLater(surveyId: 9, userIdentifier: userID)).to(beFalse())
    }

    // MARK: - Combined Behavior

    func test_shouldShowSurvey_minimumValidCase() {
        testUserDataStore.isSurveyEnabled = true
        setAppLaunchCount(3)

        expect(self.surveyService.shouldShowSurvey()).to(beTrue())
    }

    func test_shouldShowSurvey_whenLaunchIsThirdButFeatureDisabled_returnsFalse() {
        testUserDataStore.isSurveyEnabled = false
        setAppLaunchCount(3)

        expect(self.surveyService.shouldShowSurvey()).to(beFalse())
    }

    // MARK: - formatCheckboxAnswer

    func test_formatCheckboxAnswer_normalCase() {
        let result = surveyService.formatCheckboxAnswer(["Option A", "Option B"])
        expect(result).to(equal("[\"Option A\",\"Option B\"]"))
    }

    func test_formatCheckboxAnswer_emptyArray() {
        let result = surveyService.formatCheckboxAnswer([])
        expect(result).to(equal("[]"))
    }

    func test_formatCheckboxAnswer_singleItem() {
        let result = surveyService.formatCheckboxAnswer(["Only"])
        expect(result).to(equal("[\"Only\"]"))
    }

    // MARK: - Helpers

    private func setAppLaunchCount(_ count: Int) {
        for _ in 0..<count {
            testUserDataStore.incrementAppLaunchCount()
        }
    }

    private func makeSurvey(id: Int) -> Survey {
        Survey(
            id: id,
            name: "Survey \(id)",
            createdAt: Date(),
            updatedAt: Date(),
            showOnMap: true,
            showOnStops: true,
            startDate: nil,
            endDate: nil,
            visibleStopsList: nil,
            visibleRoutesList: nil,
            allowsMultipleResponses: false,
            allowsVisible: false,
            study: Study(id: 1, name: "Study", description: nil),
            questions: []
        )
    }
}
