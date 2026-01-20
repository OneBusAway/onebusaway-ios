//
//  SurveyViewHostingProtocol.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 20/01/2026.
//

import SwiftUI
import Observation
import OBAKitCore

protocol SurveyViewHostingProtocol {

    var surveysVM: SurveysViewModel { get set }

    var observationActive: Bool { get set }

    func observeSurveyHeroQuestion()

    func observeSurveysState()

    func stopObserveSurveysState()

    func observeSurveyError()

    func observeSurveyLoadingState()

    func observeSurveyFullQuestionsState()

    func observeSurveyDismissActionSheet()

    func observeSurveyToastMessage()

    func observeOpenExternalSurvey()

    func presentFullSurveyQuestions()

    func showSurveyError(_ error: Error)

    func showSurveyDismissActionSheet(_ presenter: UIViewController)

    func openSafari(with url: URL)

}

extension SurveyViewHostingProtocol where Self: UIViewController {

    func observeSurveyError() {
        withObservationTracking { [weak self] in
            if let error = self?.surveysVM.error {
                self?.showSurveyError(error)
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyError()
            }
        }
    }

    func observeSurveyLoadingState() {
        withObservationTracking {
            if surveysVM.isLoading {
                ProgressHUD.show()
            } else {
                ProgressHUD.dismiss()
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyLoadingState()
            }
        }
    }

    func observeSurveyFullQuestionsState() {
        withObservationTracking { [weak self] in
            guard let self else { return }

            if self.surveysVM.showFullSurveyQuestions {
                self.stopObserveSurveysState()
                self.presentFullSurveyQuestions()
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyFullQuestionsState()
            }
        }
    }

//    func observeSurveyDismissActionSheet() {
//        withObservationTracking { [weak self] in
//            guard let self else { return }
//            if self.surveysVM.showSurveyDismissSheet {
//                self.showSurveyDismissActionSheet()
//            }
//        } onChange: {
//            Task { @MainActor [weak self] in
//                guard let self, self.observationActive else { return }
//                self.observeSurveyDismissActionSheet()
//            }
//        }
//    }

    func observeSurveyToastMessage() {
        withObservationTracking { [weak self] in
            let showToast = self?.surveysVM.showToastMessage ?? false
            guard let self, showToast else { return }

            switch self.surveysVM.toastType {
            case .error:
                showErrorToast(surveysVM.toastMessage)
            case .success:
                showSuccessToast(surveysVM.toastMessage)
            }
            self.surveysVM.showToastMessage = false

        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyToastMessage()
            }
        }
    }

    func observeOpenExternalSurvey() {
        withObservationTracking { [weak self] in
            guard let self, self.surveysVM.openExternalSurvey, let url = self.surveysVM.externalSurveyURL else { return }
            self.openSafari(with: url)
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeOpenExternalSurvey()
            }
        }
    }

    func showSurveyError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await AlertPresenter.show(error: error, presentingController: self)
        }
    }

    func showSurveyDismissActionSheet(_ presenter: UIViewController) {
        let alertController = UIAlertController(
            title: Strings.surveyDismissAlertTitle,
            message: Strings.surveyDismissAlertBody,
            preferredStyle: .actionSheet
        )

        alertController.addAction(
            title: Strings.skipSurvey,
            style: .destructive
        ) { [weak self] _ in
            self?.surveysVM.onAction(.onSkipSurvey)
        }

        alertController.addAction(
            title: Strings.remindLater,
            style: .default
        ) { [weak self] _ in
            self?.surveysVM.onAction(.onRemindLater)
        }

        alertController.addAction(title: Strings.cancel, style: .cancel) { [weak self] _ in
            self?.surveysVM.showSurveyDismissSheet = false
        }

        presenter.present(alertController, animated: true)
    }

}
