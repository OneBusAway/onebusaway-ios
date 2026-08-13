//
//  ExternalSurveyLauncher.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Builds an external survey's destination URL via `SurveyService` and opens it,
/// marking the survey completed only when the open actually succeeds.
///
/// The open call is an injectable seam so it can be exercised in tests without
/// touching `UIApplication`.
@MainActor
struct ExternalSurveyLauncher {
    let surveyService: SurveyService

    /// Opens `url`, calling back on the main actor with whether the system handled it.
    var urlOpener: (URL, @escaping @MainActor @Sendable (Bool) -> Void) -> Void = { url, completion in
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }

    /// Builds the survey URL and attempts to open it.
    ///
    /// - Returns: `true` if a URL was built and an open attempted; `false` if no
    ///   openable URL could be produced (in which case `onFailure` is called).
    @discardableResult
    func launch(
        survey: Survey,
        stop: Stop?,
        onSuccess: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) -> Bool {
        guard let url = surveyService.externalSurveyURL(for: survey, stop: stop) else {
            Logger.error("External survey \(survey.id): no openable URL; not opening.")
            onFailure()
            return false
        }

        urlOpener(url) { success in
            if success {
                surveyService.markSurveyCompleted(survey)
                onSuccess()
            } else {
                Logger.error("External survey \(survey.id): system declined to open \(url).")
                onFailure()
            }
        }
        return true
    }
}
