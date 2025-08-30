// OBAKit/Surveys/SurveyDisplayManager.swift
//
//  SurveyDisplayManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Manages survey display across different view controllers
public class SurveyDisplayManager {
    
    private let surveyService: SurveyService
    private weak var presentingViewController: UIViewController?
    
    public init(surveyService: SurveyService) {
        self.surveyService = surveyService
    }
    
    /// Shows a survey in the specified view controller
    public func showSurvey(
        _ survey: Survey,
        in viewController: UIViewController,
        stopID: String? = nil,
        stopLocation: (latitude: Double, longitude: Double)? = nil,
        presentationStyle: SurveyPresentationStyle = .bottomSheet
    ) {
        self.presentingViewController = viewController
        
        switch presentationStyle {
        case .bottomSheet:
            showBottomSheet(survey: survey, stopID: stopID, stopLocation: stopLocation)
        case .fullScreen:
            showFullScreen(survey: survey, stopID: stopID, stopLocation: stopLocation)
        case .heroInline(let containerView):
            showHeroInline(survey: survey, in: containerView, stopID: stopID, stopLocation: stopLocation)
        }
    }
    
    private func showBottomSheet(survey: Survey, stopID: String?, stopLocation: (latitude: Double, longitude: Double)?) {
        guard let presentingViewController = presentingViewController else { return }
        
        let bottomSheet = SurveyBottomSheetController(
            survey: survey,
            surveyService: surveyService,
            stopID: stopID,
            stopLocation: stopLocation
        )
        
        presentingViewController.present(bottomSheet, animated: true)
    }
    
    private func showFullScreen(survey: Survey, stopID: String?, stopLocation: (latitude: Double, longitude: Double)?) {
        guard let presentingViewController = presentingViewController else { return }
        
        let surveyVC = SurveyViewController(
            survey: survey,
            surveyService: surveyService,
            stopID: stopID,
            stopLocation: stopLocation
        )
        
        let navigationController = UINavigationController(rootViewController: surveyVC)
        navigationController.modalPresentationStyle = .fullScreen
        
        presentingViewController.present(navigationController, animated: true)
    }
    
    private func showHeroInline(survey: Survey, in containerView: UIView, stopID: String?, stopLocation: (latitude: Double, longitude: Double)?) {
        let heroView = SurveyHeroQuestionView(
            survey: survey,
            onAnswer: { [weak self] answer in
                self?.handleHeroAnswer(survey: survey, answer: answer, stopID: stopID, stopLocation: stopLocation)
            },
            onMoreQuestions: { [weak self] in
                self?.showBottomSheet(survey: survey, stopID: stopID, stopLocation: stopLocation)
            },
            onAnswerLater: { [weak self] in
                Task { @MainActor in
                    self?.surveyService.markSurveyForLater(survey)
                    self?.removeHeroView(from: containerView)
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor in
                    self?.surveyService.dismissSurvey(survey)
                    self?.removeHeroView(from: containerView)
                }
            }
        )
        
        heroView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(heroView)
        
        NSLayoutConstraint.activate([
            heroView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            heroView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            heroView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            heroView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
        
        heroView.animateIn()
    }
    
    private func handleHeroAnswer(survey: Survey, answer: String, stopID: String?, stopLocation: (latitude: Double, longitude: Double)?) {
        guard let heroQuestion = survey.heroQuestion else { return }
        
        Task { @MainActor in
            let response = surveyService.createQuestionResponse(question: heroQuestion, answer: answer)
            
            do {
                _ = try await surveyService.submitHeroQuestion(
                    survey: survey,
                    heroQuestionResponse: response,
                    stopID: stopID,
                    stopLocation: stopLocation
                )
                
                // Mark as completed if it's a single-question survey
                if survey.remainingQuestions.isEmpty {
                    surveyService.markSurveyCompleted(survey)
                }
            } catch {
                // Handle error - maybe show an alert
                print("Error submitting hero question: \(error)")
            }
        }
    }
    
    private func removeHeroView(from containerView: UIView) {
        guard let heroView = containerView.subviews.first(where: { $0 is SurveyHeroQuestionView }) as? SurveyHeroQuestionView else { return }
        
        heroView.animateOut {
            heroView.removeFromSuperview()
        }
    }
}

// MARK: - Presentation Style
public enum SurveyPresentationStyle {
    case bottomSheet
    case fullScreen
    case heroInline(containerView: UIView)
}
