//
//  SurveyCardRepresentable.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Bridges the existing UIKit `SurveyCell` into the SwiftUI Stop page so the
/// inline hero survey renders and behaves identically to the legacy screen,
/// reusing the cell rather than reimplementing survey interaction.
///
/// Full-survey presentation (multi-question surveys) and submission-error alerts
/// are driven by the view model's Combine publishers and presented by
/// `StopPageViewController.bindSurveyPresentation()`.
struct SurveyCardRepresentable: UIViewRepresentable {
    let survey: Survey
    let stopID: String
    let onNext: (String) -> Void
    let onDismiss: () -> Void
    let onOpenExternalSurvey: () -> Void

    func makeUIView(context: Context) -> SurveyCell {
        let cell = SurveyCell(frame: .zero)
        context.coordinator.apply(to: cell, from: self)
        return cell
    }

    func updateUIView(_ uiView: SurveyCell, context: Context) {
        // Re-apply only when the survey identity changes so the cell keeps its
        // in-progress selection across unrelated SwiftUI updates.
        if context.coordinator.appliedSurveyID != survey.id {
            context.coordinator.apply(to: uiView, from: self)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SurveyCell, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingCompressedSize.width
        let fitting = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appliedSurveyID: Int?

        func apply(to cell: SurveyCell, from view: SurveyCardRepresentable) {
            let item = SurveyStopListItem(
                survey: view.survey,
                stopID: view.stopID,
                selectedOption: nil,
                onNext: view.onNext,
                onDismiss: view.onDismiss,
                onSelectionChanged: { _ in },
                onOpenExternalSurvey: view.onOpenExternalSurvey
            )
            cell.apply(SurveyContentConfiguration(item))
            appliedSurveyID = view.survey.id
        }
    }
}
