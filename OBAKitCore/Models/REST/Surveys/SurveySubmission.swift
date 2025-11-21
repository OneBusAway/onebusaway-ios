//
//  SurveySubmission.swift
//  OBAKitCore
//
//  Created by Mohamed Sliem on 20/11/2025.
//

import Foundation


public struct SurveySubmission: Codable {
    
    public let userIdentifier: String
    
    public let surveyId: Int
    
    public let stopIdentifier: String?
    
    public let stopLongitude: Double?
    
    public let stopLatitude: Double?
    
    public let responses: [QuestionAnswerSubmission]
    
    enum CodingKeys: String, CodingKey {
        case userIdentifier = "user_identifier"
        case surveyId = "survey_id"
        case stopIdentifier = "stop_identifier"
        case stopLongitude = "stop_longitude"
        case stopLatitude = "stop_latitude"
        case responses
    }
    
}

public struct QuestionAnswerSubmission: Codable {
    
    public let questionId: String
    
    public let questionType: String
    
    public let questionLabel: String
    
    public let answer: String
    
    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case questionType = "question_type"
        case questionLabel = "question_label"
        case answer
    }
}

public struct SurveySubmissionResponse: Codable {
    
    public let id: String
    
    public let updatePath: String
    
    public let userIdentifier: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case updatePath = "update_path"
        case userIdentifier = "user_identifier"
    }
    
}
