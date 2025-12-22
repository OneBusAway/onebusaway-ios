//
//  SurveyAnswer.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 22/12/2025.
//

import Foundation

enum SurveyQuestionAnswer: Hashable {

    case text(String)

    case radio(_ selectedOption: String)

    case checkbox(_ selectedOptions: Set<String>)

}

extension SurveyQuestionAnswer {
    var stringValue: String {
        switch self {

        case .text(let value):
            return value

        case .radio(let option):
            return option

        case .checkbox(let options):
            return options.sorted().joined(separator: ", ")

        }
    }
}
