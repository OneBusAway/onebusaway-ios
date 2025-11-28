//
//  SurveyPreferences.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

struct SurveyPreferences: Codable {

    /// Whether the user has enabled the surveys feature.
    var isSurveyEnabled: Bool = true

    /// IDs of surveys that the user has completed.
    var completedSurveyIDs: [Int]

    /// IDs of surveys the user intentionally skipped.
    var skippedSurveyIDs: [Int]

    /// The next date at which the user should be reminded to take a survey.
    var nextReminderDate: Date?

    /// The ID of a survey that was in progress but not completed due to an unexpected interruption.
    var pendingSurveyID: Int?

}
