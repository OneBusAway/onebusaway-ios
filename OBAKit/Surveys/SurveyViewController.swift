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
import SwiftUI
import UIKit
import OBAKitCore

/// Presents a survey. The form is `SurveyView`; this controller owns the
/// Close button, the outcome alerts, and dismissal.
class SurveyViewController: UIHostingController<SurveyView> {

    private let viewModel: SurveyViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: SurveyViewModel) {
        self.viewModel = viewModel
        super.init(rootView: SurveyView(viewModel: viewModel, openExternalSurvey: {}))
        // The button needs `self`, which doesn't exist until `super.init` returns.
        rootView = SurveyView(viewModel: viewModel, openExternalSurvey: { [weak self] in self?.openExternalSurvey() })

        title = viewModel.survey.name
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(cancelTapped)
        )
        bindViewModel()
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

    private func bindViewModel() {
        viewModel.submissionResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                switch result {
                case .success:
                    self?.dismiss(animated: true)
                case .failure(.validationFailed):
                    self?.showValidationError()
                case .failure(.malformedSurveyData):
                    self?.showMalformedSurveyError()
                case .failure(.submissionFailed(let error)):
                    self?.showSubmissionError(error)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func cancelTapped() {
        viewModel.cancel()
        dismiss(animated: true)
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

    private func showMalformedSurveyError() {
        Logger.error("Survey \(viewModel.survey.id) is malformed (no answerable hero question on the fresh path).")
        let alert = UIAlertController(
            title: OBALoc("survey_vc.malformed_error.title", value: "Survey Unavailable", comment: "Title for malformed survey alert"),
            message: OBALoc("survey_vc.malformed_error.message", value: "This survey can't be submitted right now. Please try again later.", comment: "Message when the survey data itself is malformed (no answerable hero question)."),
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
