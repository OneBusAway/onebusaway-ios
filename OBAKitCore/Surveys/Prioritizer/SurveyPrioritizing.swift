//
//  SurveyPrioritizing.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 29/11/2025.
//

import Foundation

public protocol SurveyPrioritizing {

    func nextSurveyIndex(_ surveys: [Survey], visibleOnStop: Bool, stop: Stop?) -> Int

}
