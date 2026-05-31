//
//  SurveyViewController.swift
//  OBAKit
//
//  Copyright Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import UIKit
import Eureka
import OBAKitCore

class SurveyViewController: FormViewController {

    private let viewModel: SurveyViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: SurveyViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(
        survey: Survey,
        surveyService: SurveyService,
        stop: Stop? = nil,
        stopID: String? = nil,
        stopLocation: CLLocationCoordinate2D? = nil,
        heroResponseID: String? = nil
    ) {
        self.init(viewModel: SurveyViewModel(
            survey: survey,
            surveyService: surveyService,
            stop: stop,
            stopID: stopID,
            stopLocation: stopLocation,
            heroResponseID: heroResponseID
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupForm()
        bindViewModel()
    }

    private func setupNavigationBar() {
        title = viewModel.survey.name
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(cancelTapped)
        )
    }

    private func bindViewModel() {
        viewModel.submissionResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                switch result {
                case .success:
                    self?.dismiss(animated: true)
                case .failure(.validationFailed):
                    self?.showValidationError()
                case .failure(.network(let error)):
                    self?.showSubmissionError(error)
                }
            }
            .store(in: &cancellables)
    }

    private func setupForm() {
        // Header section with survey info
        form +++ Section()
        <<< LabelRow("survey_header") { row in
            row.title = viewModel.survey.study.description
            row.cell.textLabel?.numberOfLines = 0
        }

        // Questions section
        let questionsSection = Section(OBALoc("survey_vc.questions_section_title", value: "Questions", comment: "Section header for survey questions"))
        form +++ questionsSection

        for question in viewModel.questionsToShow {
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
                        self?.viewModel.updateAnswer(for: question, answer: value)
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
                            self.viewModel.updateAnswer(for: question, answer: option)
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
            for (index, option) in options.enumerated() {
                let optionTag = "\(questionTag)_checkbox_\(index)"
                section <<< CheckRow(optionTag) { row in
                    row.title = option
                    row.value = false
                }.onChange { [weak self] row in
                    self?.viewModel.toggleCheckbox(option: option, selected: row.value == true, for: question)
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
                    self?.viewModel.updateAnswer(for: question, answer: value)
                }
            }

        case .externalSurvey:
            section <<< LabelRow("\(questionTag)_label") { row in
                row.title = question.content.labelText
                row.cell.textLabel?.numberOfLines = 0
            }

            section <<< ButtonRow(questionTag) { row in
                row.title = OBALoc("survey_vc.open_external_survey_button", value: "Open Survey", comment: "Button that opens an external survey in the browser")
                row.onCellSelection { [weak self] _, _ in
                    self?.openExternalSurvey()
                }
            }
        }
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        Task { await viewModel.submit() }
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
        let alert = UIAlertController(
            title: OBALoc("survey_vc.submission_error.title", value: "Submission Error", comment: "Title for survey submission error alert"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("survey_vc.ok_button", value: "OK", comment: "OK button on survey alerts"), style: .default))
        present(alert, animated: true)
    }

    private func openExternalSurvey() {
        viewModel.launchExternalSurvey(
            onSuccess: { [weak self] in self?.dismiss(animated: true) },
            // On failure, keep the form on screen so the rider can retry; the
            // launcher does not mark the survey completed unless the open succeeds.
            onFailure: { [weak self] in self?.showExternalSurveyError() }
        )
    }

    private func showExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("survey_vc.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("survey_vc.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OBALoc("survey_vc.ok_button", value: "OK", comment: "OK button on survey alerts"), style: .default))
        present(alert, animated: true)
    }
}
