//
//  SurveyPreferences.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

public struct SurveyPreferences: Codable {

    public var userSurveyId: String?

    /// Whether the user has enabled the surveys feature.
    public var isSurveyEnabled: Bool = true

    /// IDs of surveys that the user has completed.
    public var completedSurveyIDs: Set<Int> = []

    /// IDs of surveys the user intentionally skipped.
    public var skippedSurveyIDs: Set<Int> = []

    /// The next date at which the user should be reminded to take a survey.
    public var nextReminderDate: Date?

    public init(
        userSurveyId: String? = nil,
        isSurveyEnabled: Bool = true,
        completedSurveyIDs: Set<Int> = [],
        skippedSurveyIDs: Set<Int> = [],
        nextReminderDate: Date? = nil,
    ) {
        self.userSurveyId = userSurveyId
        self.isSurveyEnabled = isSurveyEnabled
        self.completedSurveyIDs = completedSurveyIDs
        self.skippedSurveyIDs = skippedSurveyIDs
        self.nextReminderDate = nextReminderDate
    }
}
