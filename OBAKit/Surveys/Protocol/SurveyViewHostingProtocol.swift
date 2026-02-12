//
//  SurveyViewHostingProtocol.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 20/01/2026.
//

import SwiftUI
import Observation
import OBAKitCore
import SafariServices

@MainActor
protocol SurveyViewHostingProtocol {

    var surveysVM: SurveysViewModel { get set }

    var observationActive: Bool { get set }

    func observeSurveyHeroQuestion()

    func observeSurveysState()

    func stopObserveSurveysState()

    func observeSurveyLoadingState()

    func observeSurveyFullQuestionsState(_ router: ViewRouter)

    func observeSurveyDismissActionSheet()

    func observeSurveyToastMessage()

    func observeOpenExternalSurvey(_ router: ViewRouter)

    func presentFullSurveyQuestions(_ router: ViewRouter)

    func showSurveyDismissActionSheet()

    func openSafari(with url: URL, router: ViewRouter)

}

extension SurveyViewHostingProtocol where Self: UIViewController {

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

    func observeSurveyFullQuestionsState(_ router: ViewRouter) {
        withObservationTracking { [weak self] in
            guard let self else { return }

            if self.surveysVM.showFullSurveyQuestions {
                self.stopObserveSurveysState()
                self.presentFullSurveyQuestions(router)
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyFullQuestionsState(router)
            }
        }
    }

    func observeSurveyToastMessage() {
        withObservationTracking { [weak self] in
            let showToast = self?.surveysVM.showToastMessage ?? false
            let type = self?.surveysVM.toast?.type

            guard let self, let type = type, showToast else { return }

            switch type {
            case .error:
                showErrorToast(surveysVM.toast?.message)
            case .success:
                showSuccessToast(surveysVM.toast?.message)
            }

        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyToastMessage()
            }
        }
    }

    func observeOpenExternalSurvey(_ router: ViewRouter) {
        withObservationTracking { [weak self] in
            guard let self, self.surveysVM.openExternalSurvey, let url = self.surveysVM.externalSurveyURL else { return }
            self.openSafari(with: url, router: router)
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeOpenExternalSurvey(router)
            }
        }
    }

    func showSurveyDismissActionSheet() {
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
            self?.surveysVM.onAction(.hideSurveyDismissSheet)
        }

        self.present(alertController, animated: true)
    }

    func presentFullSurveyQuestions(_ router: ViewRouter) {
        let surveyQuestionsForm = SurveyQuestionsForm(viewModel: self.surveysVM) { [weak self] in
            self?.observeSurveysState()
        }

        let hosting = UIHostingController(rootView: surveyQuestionsForm)
        router.present(hosting, from: self, isModal: true, isPopover: true)
    }

    func openSafari(with url: URL, router: ViewRouter) {
        let safariView = SFSafariViewController(url: url)
        router.present(safariView, from: self, isModal: true)
    }

    func observeSurveyDismissActionSheet() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            if self.surveysVM.showSurveyDismissSheet {
                self.showSurveyDismissActionSheet()
            }
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.observationActive else { return }
                self.observeSurveyDismissActionSheet()
            }
        }
    }

}
