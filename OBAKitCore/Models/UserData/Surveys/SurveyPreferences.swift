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
    public var completedSurveyIDs: [Int] = []

    /// IDs of surveys the user intentionally skipped.
    public var skippedSurveyIDs: [Int] = []

    /// The next date at which the user should be reminded to take a survey.
    public var nextReminderDate: Date?

    /// The ID of a survey that was in progress but not completed due to an unexpected interruption.
    public var pendingSurveyID: Int?

    public init(
        userSurveyId: String? = nil,
        isSurveyEnabled: Bool = true,
        completedSurveyIDs: [Int] = [],
        skippedSurveyIDs: [Int] = [],
        nextReminderDate: Date? = nil,
        pendingSurveyID: Int? = nil
    ) {
        self.userSurveyId = userSurveyId
        self.isSurveyEnabled = isSurveyEnabled
        self.completedSurveyIDs = completedSurveyIDs
        self.skippedSurveyIDs = skippedSurveyIDs
        self.nextReminderDate = nextReminderDate
        self.pendingSurveyID = pendingSurveyID
    }
}
