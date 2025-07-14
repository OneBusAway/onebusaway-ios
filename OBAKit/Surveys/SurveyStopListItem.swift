// OBAKit/Surveys/SurveyStopListItem.swift
//
//  SurveyStopListItem.swift
//  OBAKit
//
//  Copyright Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore
import UIKit

/// List item that displays a survey in the stop view with interactive hero question
struct SurveyStopListItem: OBAListViewItem {
    var configuration: OBAListViewItemConfiguration {
        return .custom(SurveyContentConfiguration(self))
    }

    static var customCellType: OBAListViewCell.Type? {
        return SurveyCell.self
    }

    let id = UUID()
    let survey: Survey
    let stopID: String?
    
    // State management (inspired by previous implementation)
    var selectedOption: String?
    
    // Actions - simplified to just one next action
    let onNext: (String) -> Void  // Called when next is tapped with selected option
    let onDismiss: () -> Void
    let onSelectionChanged: (String?) -> Void
    
    // MARK: - Initializer
    init(
        survey: Survey,
        stopID: String?,
        selectedOption: String? = nil,
        onNext: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void,
        onSelectionChanged: @escaping (String?) -> Void
    ) {
        self.survey = survey
        self.stopID = stopID
        self.selectedOption = selectedOption
        self.onNext = onNext
        self.onDismiss = onDismiss
        self.onSelectionChanged = onSelectionChanged
    }
    
    // Legacy compatibility - map old actions to new ones
    init(
        survey: Survey,
        stopID: String?,
        selectedOption: String? = nil,
        onAnswer: @escaping (String) -> Void,
        onMoreQuestions: @escaping () -> Void,
        onAnswerLater: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onSelectionChanged: @escaping (String?) -> Void
    ) {
        self.survey = survey
        self.stopID = stopID
        self.selectedOption = selectedOption
        // Map the more questions action to our next action, but only if there's a selection
        self.onNext = { selectedOption in
            onAnswer(selectedOption)
            onMoreQuestions()
        }
        self.onDismiss = onDismiss
        self.onSelectionChanged = onSelectionChanged
    }
}

// MARK: - Protocol Conformances
extension SurveyStopListItem: Equatable {
    static func == (lhs: SurveyStopListItem, rhs: SurveyStopListItem) -> Bool {
        return lhs.id == rhs.id &&
               lhs.survey.id == rhs.survey.id &&
               lhs.selectedOption == rhs.selectedOption
    }
}

extension SurveyStopListItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(survey.id)
        hasher.combine(selectedOption)
    }
}

extension SurveyStopListItem: Identifiable {
    // Already has `let id = UUID()`
}

// MARK: - Content Configuration
struct SurveyContentConfiguration: OBAContentConfiguration {
    var formatters: OBAKitCore.Formatters?

    var viewModel: SurveyStopListItem

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return SurveyCell.self
    }

    init(_ viewModel: SurveyStopListItem) {
        self.viewModel = viewModel
    }
}