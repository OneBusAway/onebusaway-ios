// OBAKit/Surveys/SurveyDisplayManager.swift
//
//  SurveyDisplayManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
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
        stopLocation: CLLocationCoordinate2D? = nil,
        presentationStyle: SurveyPresentationStyle = .bottomSheet
    ) {
        self.presentingViewController = viewController

        switch presentationStyle {
        case .bottomSheet:
            showBottomSheet(survey: survey, stopID: stopID, stopLocation: stopLocation)
        }
    }

    private func showBottomSheet(survey: Survey, stopID: String?, stopLocation: CLLocationCoordinate2D?) {
        guard let presentingViewController = presentingViewController else {
            Logger.warn("Cannot present survey bottom sheet: presentingViewController was deallocated")
            return
        }

        let bottomSheet = SurveyBottomSheetController(
            survey: survey,
            surveyService: surveyService,
            stopID: stopID,
            stopLocation: stopLocation
        )

        presentingViewController.present(bottomSheet, animated: true)
    }
}

// MARK: - Presentation Style
public enum SurveyPresentationStyle {
    case bottomSheet
}
