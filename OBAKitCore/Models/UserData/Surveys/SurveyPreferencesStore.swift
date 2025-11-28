//
//  SurveyPreferencesStore.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 28/11/2025.
//

import Foundation

protocol SurveyPreferencesStore: NSObjectProtocol {

    var appLaunch: Int { get }
    
    func increaseAppLaunchCount()

    var completedSurveys: [Int] { get }

    var skippedSurveys: [Int] { get }
        
    func setSurveyPreferences(_ preferences: SurveyPreferences)

    func surveyPreferences() -> SurveyPreferences?

}
