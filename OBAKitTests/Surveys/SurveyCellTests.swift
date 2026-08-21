//
//  SurveyCellTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Covers the inline stop-page survey card's Next-button gating.
///
/// A `.label` hero question is display-only — there is no option to pick and no
/// field to fill in — so gating Next on a stored selection left the button
/// permanently disabled and the card impossible to advance past.
@Suite(.serialized)
@MainActor
struct SurveyCellTests {

    /// Records the card's callbacks. `SurveyStopListItem` is a `nonisolated`
    /// struct, so the closures it stores are nonisolated too and cannot touch a
    /// (default-main-actor) test-local box — hence the explicit `nonisolated`.
    nonisolated private final class Recorder {
        var nextAnswers: [String] = []
        var dismissCount = 0
    }

    private func makeCell(
        type: QuestionType,
        options: [String]? = nil,
        recorder: Recorder
    ) -> SurveyCell {
        // `heroQuestion` is the question at position 1.
        let hero = SurveysTestHelpers.makeSurveyQuestion(
            id: 1,
            position: 1,
            type: type,
            labelText: "Share your transit story",
            options: options
        )
        let item = SurveyStopListItem(
            survey: SurveysTestHelpers.makeSurvey(questions: [hero]),
            stopID: "1_11370",
            onNext: { recorder.nextAnswers.append($0) },
            onDismiss: { recorder.dismissCount += 1 },
            onSelectionChanged: { _ in }
        )

        let cell = SurveyCell(frame: .zero)
        cell.apply(SurveyContentConfiguration(item))
        return cell
    }

    @Test func `Next is enabled for a label hero question`() {
        let cell = makeCell(type: .label, recorder: Recorder())

        #expect(cell.nextButton.isEnabled)
    }

    /// A label collects no answer, so advancing submits an empty one rather than
    /// dropping the tap.
    @Test func `Tapping Next on a label hero question submits an empty answer`() {
        let recorder = Recorder()
        let cell = makeCell(type: .label, recorder: recorder)

        cell.nextButton.sendActions(for: .touchUpInside)

        #expect(recorder.nextAnswers == [""])
    }

    /// Regression guard for the answerable case: a radio hero question still has
    /// to be answered before Next does anything.
    @Test func `Next stays inert until a radio option is selected`() {
        let recorder = Recorder()
        let cell = makeCell(type: .radio, options: ["Yes", "No"], recorder: recorder)

        #expect(!cell.nextButton.isEnabled)

        cell.nextButton.sendActions(for: .touchUpInside)
        #expect(recorder.nextAnswers.isEmpty)
    }
}
