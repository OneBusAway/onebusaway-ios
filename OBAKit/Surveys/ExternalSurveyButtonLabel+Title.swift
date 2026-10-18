//
//  ExternalSurveyButtonLabel+Title.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

extension ExternalSurveyButtonLabel {
    /// The title of the button that opens an external survey, shared by the
    /// stop-page card and the full survey screen.
    var localizedTitle: String {
        switch self {
        case .openSurvey:
            OBALoc("external_survey_button.open_survey", value: "Open Survey", comment: "Button that opens an external survey in the browser")
        case .learnMore:
            Strings.learnMore
        case .shareFeedback:
            OBALoc("external_survey_button.share_feedback", value: "Share Feedback", comment: "Button that opens an external feedback form in the browser")
        case .signUp:
            OBALoc("external_survey_button.sign_up", value: "Sign Up", comment: "Button that opens an external sign-up form in the browser")
        }
    }
}
