//
//  SurveyError.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum SurveyError: Error, LocalizedError {

    case serviceUnavailable

    case missingUpdatePath

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return Strings.surveyServiceNotAvailable
        case .missingUpdatePath:
            return Strings.surveyMissingUpdatePath
        }
    }

}
