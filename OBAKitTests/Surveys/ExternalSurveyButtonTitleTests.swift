//
//  ExternalSurveyButtonTitleTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The external survey button's title follows the question's `button_label`,
/// on both the stop-page card and the full survey screen.
@Suite(.serialized)
@MainActor
struct ExternalSurveyButtonTitleTests {

    @Test(arguments: [
        (ExternalSurveyButtonLabel.openSurvey, "Open Survey"),
        (.learnMore, "Learn More"),
        (.shareFeedback, "Share Feedback"),
        (.signUp, "Sign Up")
    ])
    func `Each label has an English title`(label: ExternalSurveyButtonLabel, title: String) {
        #expect(label.localizedTitle == title)
    }

    private func makeCell(buttonLabel: String?) -> SurveyCell {
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            position: 1,
            type: .externalSurvey,
            url: "https://example.com/survey",
            buttonLabel: buttonLabel
        )
        let item = SurveyStopListItem(
            survey: SurveysTestHelpers.makeSurvey(questions: [hero]),
            stopID: "1_11370",
            onNext: { _ in },
            onDismiss: {},
            onSelectionChanged: { _ in }
        )
        let cell = SurveyCell(frame: .zero)
        cell.apply(SurveyContentConfiguration(item))
        return cell
    }

    @Test func `Stop card uses the question's button label`() {
        let cell = makeCell(buttonLabel: "learn_more")

        #expect(!cell.externalSurveyButton.isHidden)
        #expect(cell.externalSurveyButton.configuration?.title == "Learn More")
    }

    @Test func `Stop card shows Open Survey without a button label`() {
        let cell = makeCell(buttonLabel: nil)

        #expect(cell.externalSurveyButton.configuration?.title == "Open Survey")
    }

    @Test func `Stop card shows Open Survey for an unknown button label`() {
        let cell = makeCell(buttonLabel: "book_a_ride")

        #expect(cell.externalSurveyButton.configuration?.title == "Open Survey")
    }
}
