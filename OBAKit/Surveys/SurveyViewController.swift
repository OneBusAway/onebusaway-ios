//
//  SurveyViewController.swift
//  OBAKit
//
//  Copyright Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Eureka
import OBAKitCore

class SurveyViewController: FormViewController {
    
    private let survey: Survey
    private let surveyService: SurveyServiceProtocol
    private let stopID: String?
    private let stopLocation: (latitude: Double, longitude: Double)?
    
    private var responses: [SurveyQuestionResponse] = []
    private var heroResponseID: String?
    
    init(survey: Survey, surveyService: SurveyServiceProtocol, stopID: String? = nil, stopLocation: (latitude: Double, longitude: Double)? = nil) {
        self.survey = survey
        self.surveyService = surveyService
        self.stopID = stopID
        self.stopLocation = stopLocation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupForm()
    }
    
    private func setupNavigationBar() {
        title = survey.name
        // Remove Cancel and Done buttons - user can swipe down to dismiss the bottom sheet
        // navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        // navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(submitTapped))
    }
    
    private func setupForm() {
        // Header section with survey info
        form +++ Section()
        <<< LabelRow("survey_header") { row in
            row.title = survey.study.description
            row.cell.textLabel?.numberOfLines = 0
        }
        
        // Questions section
        let questionsSection = Section("Questions")
        form +++ questionsSection
        
        // Skip hero question if already answered
        let questionsToShow = heroResponseID != nil ? survey.remainingQuestions : survey.questions
        
        for question in questionsToShow {
            addQuestionRow(question, to: questionsSection)
        }
        
        // Actions section
        form +++ Section()
        <<< ButtonRow("submit") { row in
            row.title = "Submit Survey"
            row.onCellSelection { [weak self] _, _ in
                self?.submitTapped()
            }
        }
    }
    
    private func addQuestionRow(_ question: SurveyQuestion, to section: Section) {
        let questionTag = "question_\(question.id)"
        
        switch question.content {
        case .label(let text):
            section <<< LabelRow(questionTag) { row in
                row.title = text
                row.cell.textLabel?.numberOfLines = 0
            }
            
        case .radio(let labelText, let options):
            // Add question label
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }
            
            // Use SegmentedRow for inline options instead of ActionSheetRow
            if options.count <= 3 {
                // Use segmented control for few options
                section <<< SegmentedRow<String>(questionTag) { row in
                    row.options = options
                    row.value = nil
                }.onChange { [weak self] row in
                    if let value = row.value {
                        self?.updateResponse(for: question, answer: value)
                    }
                }
            } else {
                // Use individual radio button rows for many options
                for (index, option) in options.enumerated() {
                    let optionTag = "\(questionTag)_option_\(index)"
                    section <<< CheckRow(optionTag) { row in
                        row.title = option
                        row.value = false
                    }.onChange { [weak self] row in
                        guard let self = self else { return }
                        
                        if row.value == true {
                            // Uncheck other options (radio button behavior)
                            for (otherIndex, _) in options.enumerated() {
                                if otherIndex != index {
                                    let otherTag = "\(questionTag)_option_\(otherIndex)"
                                    if let otherRow = self.form.rowBy(tag: otherTag) as? CheckRow {
                                        otherRow.value = false
                                        otherRow.updateCell()
                                    }
                                }
                            }
                            
                            // Update response
                            self.updateResponse(for: question, answer: option)
                        }
                    }
                }
            }
            
        case .checkbox(let labelText, let options):
            // Add question label
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }
            
            // Add individual checkbox options
            var selectedOptions: [String] = []
            for (index, option) in options.enumerated() {
                let optionTag = "\(questionTag)_checkbox_\(index)"
                section <<< CheckRow(optionTag) { row in
                    row.title = option
                    row.value = false
                }.onChange { [weak self] row in
                    guard let self = self else { return }
                    
                    if row.value == true {
                        selectedOptions.append(option)
                    } else {
                        selectedOptions.removeAll { $0 == option }
                    }
                    
                    let jsonAnswer = self.formatCheckboxAnswer(selectedOptions)
                    self.updateResponse(for: question, answer: jsonAnswer)
                }
            }
            
        case .text(let labelText):
            // Add question label first
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }
            
            // Then add the text input
            section <<< TextAreaRow(questionTag) { row in
                row.placeholder = "Enter your answer..."
                row.textAreaHeight = .dynamic(initialTextViewHeight: 60)
            }.onChange { [weak self] row in
                if let value = row.value {
                    self?.updateResponse(for: question, answer: value)
                }
            }
        }
    }
    
    private func updateResponse(for question: SurveyQuestion, answer: String) {
        // Remove existing response for this question
        responses.removeAll { $0.questionId == question.id }
        
        // Add new response
        let response = surveyService.createQuestionResponse(question: question, answer: answer)
        responses.append(response)
    }
    
    private func formatCheckboxAnswer(_ selections: [String]) -> String {
        do {
            let jsonData = try JSONEncoder().encode(selections)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func submitTapped() {
        Task {
            await submitSurvey()
        }
    }
    
    private func submitSurvey() async {
        // Validate required questions
        guard validateResponses() else {
            showValidationError()
            return
        }
        
        do {
            if let heroResponseID = heroResponseID {
                // Submit additional questions
                if let mockService = surveyService as? MockSurveyService {
                    _ = try await mockService.submitAdditionalQuestions(
                        responseID: heroResponseID,
                        additionalResponses: responses
                    )
                } else if let realService = surveyService as? SurveyService {
                    _ = try await realService.submitAdditionalQuestions(
                        responseID: heroResponseID,
                        additionalResponses: responses
                    )
                }
            } else {
                // Submit complete survey
                guard let heroQuestion = survey.heroQuestion,
                      let heroResponse = responses.first(where: { $0.questionId == heroQuestion.id }) else {
                    showValidationError()
                    return
                }
                
                let submissionResponse = try await surveyService.submitHeroQuestion(
                    survey: survey,
                    heroQuestionResponse: heroResponse,
                    stopID: stopID,
                    stopLocation: stopLocation
                )
                
                // Submit remaining questions if any
                let remainingResponses = responses.filter { $0.questionId != heroQuestion.id }
                if !remainingResponses.isEmpty {
                    if let mockService = surveyService as? MockSurveyService {
                        _ = try await mockService.submitAdditionalQuestions(
                            responseID: submissionResponse.id,
                            additionalResponses: remainingResponses
                        )
                    } else if let realService = surveyService as? SurveyService {
                        _ = try await realService.submitAdditionalQuestions(
                            responseID: submissionResponse.id,
                            additionalResponses: remainingResponses
                        )
                    }
                }
            }
            
            surveyService.markSurveyCompleted(survey)
            dismiss(animated: true)
            
        } catch {
            showSubmissionError(error)
        }
    }
    
    private func validateResponses() -> Bool {
        let requiredQuestions = survey.questions.filter { $0.required }
        let answeredQuestionIDs = Set(responses.map { $0.questionId })
        
        for question in requiredQuestions {
            if !answeredQuestionIDs.contains(question.id) {
                return false
            }
        }
        
        return true
    }
    
    private func showValidationError() {
        let alert = UIAlertController(
            title: "Incomplete Survey",
            message: "Please answer all required questions before submitting.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showSubmissionError(_ error: Error) {
        let alert = UIAlertController(
            title: "Submission Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
