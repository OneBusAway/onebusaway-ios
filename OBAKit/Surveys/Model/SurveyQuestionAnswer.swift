//
//  SurveyAnswer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum SurveyQuestionAnswer: Hashable {

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
