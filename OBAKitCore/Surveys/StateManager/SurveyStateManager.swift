//
//  SurveyStateManager.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

final class SurveyStateManager: SurveysStateProtocol {

    /// Store responsible for persisting survey preferences.
    private var surveyStore: SurveyPreferencesStore

    /// Initializes the manager with a survey preferences store.
    /// - Parameter surveyStore: The store used to read and update survey preferences.
    init(surveyStore: SurveyPreferencesStore) {
        self.surveyStore = surveyStore
    }

    /// Determines whether a survey should be shown to the user.
    /// Returns`true` if the survey feature is enabled, the app launch count meets the trigger (every 3rd launch),
    /// and the next reminder date exists and has passed; otherwise `false`.
    func shouldShowSurvey() -> Bool {
        let preferences = surveyStore.surveyPreferences()

        // Survey feature must be enabled and current launch count must satisfy the modulo condition.
        guard preferences.isSurveyEnabled && surveyStore.appLaunch > 0 && surveyStore.appLaunch % 3 == 0 else {
            return false
        }

        if let reminderDate = preferences.nextReminderDate, reminderDate > Date.now {
            return false
        }

        return true
    }

    /// Sets the next reminder date for showing surveys.
    /// - Notes:
    ///   - Uses calendar-aware addition of 3 days to account for daylight saving time.
    ///   - Falls back to adding 72 hours if calendar calculation fails.
    func setNextReminderDate() {
        let fallback = Date().addingTimeInterval(86400 * 3)
        let nextReminderDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? fallback

        var preferences = surveyStore.surveyPreferences()
        preferences.nextReminderDate = nextReminderDate
        surveyStore.setSurveyPreferences(preferences)
    }

    /// Marks a survey as completed by the user.
    /// - Parameter surveyID: The ID of the completed survey.
    func setSurveyCompleted(_ surveyID: Int) {
        var preferences = surveyStore.surveyPreferences()
        preferences.completedSurveyIDs.append(surveyID)
        surveyStore.setSurveyPreferences(preferences)
    }

    /// Marks a survey as skipped by the user.
    /// - Parameter surveyID: The ID of the skipped survey.
    func setSurveySkipped(_ surveyID: Int) {
        var preferences = surveyStore.surveyPreferences()
        preferences.skippedSurveyIDs.append(surveyID)
        surveyStore.setSurveyPreferences(preferences)
    }

}
