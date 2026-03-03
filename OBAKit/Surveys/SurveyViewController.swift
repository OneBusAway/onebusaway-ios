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
    private let surveyService: SurveyService
    private let stopID: String?
    private let stopLocation: (latitude: Double, longitude: Double)?

    private var responses: [SurveyQuestionResponse] = []
    private var heroResponseID: String?
    private var checkboxSelections: [Int: Set<String>] = [:]

    init(survey: Survey, surveyService: SurveyService, stopID: String? = nil, stopLocation: (latitude: Double, longitude: Double)? = nil) {
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(cancelTapped)
        )
    }

    private func setupForm() {
        // Header section with survey info
        form +++ Section()
        <<< LabelRow("survey_header") { row in
            row.title = survey.study.description
            row.cell.textLabel?.numberOfLines = 0
        }

        // Questions section
        let questionsSection = Section(OBALoc("survey_vc.questions_section_title", value: "Questions", comment: "Section header for survey questions"))
        form +++ questionsSection

        // Skip hero question if already answered
        let questionsToShow = heroResponseID != nil ? survey.remainingQuestions : survey.questions

        for question in questionsToShow {
            addQuestionRow(question, to: questionsSection)
        }

        // Actions section
        form +++ Section()
        <<< ButtonRow("submit") { row in
            row.title = OBALoc("survey_vc.submit_button", value: "Submit Survey", comment: "Button to submit the survey")
            row.onCellSelection { [weak self] _, _ in
                self?.submitTapped()
            }
        }
    }

    private func addQuestionRow(_ question: SurveyQuestion, to section: Section) {
        let questionTag = "question_\(question.id)"

        switch question.content.type {
        case .label:
            section <<< LabelRow(questionTag) { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
            }

        case .radio:
            let options = question.content.options ?? []
            // Add question label
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }

            // Use SegmentedRow for inline options instead of ActionSheetRow
            if options.count <= 3 {
                section <<< SegmentedRow<String>(questionTag) { row in
                    row.options = options
                    row.value = nil
                }.onChange { [weak self] row in
                    if let value = row.value {
                        self?.updateResponse(for: question, answer: value)
                    }
                }
            } else {
                for (index, option) in options.enumerated() {
                    let optionTag = "\(questionTag)_option_\(index)"
                    section <<< CheckRow(optionTag) { row in
                        row.title = option
                        row.value = false
                    }.onChange { [weak self] row in
                        guard let self = self else { return }

                        if row.value == true {
                            for (otherIndex, _) in options.enumerated() {
                                if otherIndex != index {
                                    let otherTag = "\(questionTag)_option_\(otherIndex)"
                                    if let otherRow = self.form.rowBy(tag: otherTag) as? CheckRow {
                                        otherRow.value = false
                                        otherRow.updateCell()
                                    }
                                }
                            }
                            self.updateResponse(for: question, answer: option)
                        }
                    }
                }
            }

        case .checkbox:
            let options = question.content.options ?? []
            // Add question label
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }

            // Add individual checkbox options
            checkboxSelections[question.id] = []
            for (index, option) in options.enumerated() {
                let optionTag = "\(questionTag)_checkbox_\(index)"
                section <<< CheckRow(optionTag) { row in
                    row.title = option
                    row.value = false
                }.onChange { [weak self] row in
                    guard let self = self else { return }

                    if row.value == true {
                        self.checkboxSelections[question.id, default: []].insert(option)
                    } else {
                        self.checkboxSelections[question.id, default: []].remove(option)
                    }

                    let selections = Array(self.checkboxSelections[question.id, default: []])
                    let jsonAnswer = self.surveyService.formatCheckboxAnswer(selections)
                    self.updateResponse(for: question, answer: jsonAnswer)
                }
            }

        case .text:
            // Add question label first
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = .boldSystemFont(ofSize: 16)
            }

            // Then add the text input
            section <<< TextAreaRow(questionTag) { row in
                row.placeholder = OBALoc("survey_vc.text_placeholder", value: "Enter your answer...", comment: "Placeholder for text answer field")
                row.textAreaHeight = .dynamic(initialTextViewHeight: 60)
            }.onChange { [weak self] row in
                if let value = row.value {
                    self?.updateResponse(for: question, answer: value)
                }
            }

        case .externalSurvey:
            section <<< LabelRow(questionTag) { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
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
                _ = try await surveyService.submitAdditionalQuestions(
                    responseID: heroResponseID,
                    additionalResponses: responses
                )
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

                // Save hero response ID so retry skips re-submitting the hero
                self.heroResponseID = submissionResponse.id

                // Submit remaining questions if any
                let remainingResponses = responses.filter { $0.questionId != heroQuestion.id }
                if !remainingResponses.isEmpty {
                    _ = try await surveyService.submitAdditionalQuestions(
                        responseID: submissionResponse.id,
                        additionalResponses: remainingResponses
                    )
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
            title: OBALoc("survey_vc.validation_error.title", value: "Incomplete Survey", comment: "Title for incomplete survey alert"),
            message: OBALoc("survey_vc.validation_error.message", value: "Please answer all required questions before submitting.", comment: "Message when required survey questions are unanswered"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("survey_vc.ok_button", value: "OK", comment: "OK button on survey alerts"), style: .default))
        present(alert, animated: true)
    }

    private func showSubmissionError(_ error: Error) {
        Logger.error("Survey \(survey.id) submission failed: \(error)")
        let alert = UIAlertController(
            title: OBALoc("survey_vc.submission_error.title", value: "Submission Error", comment: "Title for survey submission error alert"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("survey_vc.ok_button", value: "OK", comment: "OK button on survey alerts"), style: .default))
        present(alert, animated: true)
    }
}
