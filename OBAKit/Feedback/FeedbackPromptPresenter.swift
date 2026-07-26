//
//  FeedbackPromptPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MessageUI
import OBAKitCore
import UIKit

/// Presents the two-step feedback prompt and routes the rider to either the App
/// Store review form or a pre-filled feedback email.
///
/// The positive branch opens Apple's documented `?action=write-review` deep link
/// rather than calling `AppStore.requestReview(in:)`. Apple's own guidance says
/// to "avoid requesting a review as the result of a user action" — `requestReview`
/// may display nothing at all, which would leave a rider who just tapped "Yes!"
/// staring at an unchanged screen. The deep link is guaranteed to land them on
/// the review form and isn't subject to the three-per-365-days budget. See
/// docs/superpowers/specs/2026-07-25-feedback-prompt-design.md — "Apple's constraints"
/// for the quoted guidance and the 3-per-365 budget, §10 for the guideline 5.6.1
/// analysis and why `AppStore.requestReview(in:)` was rejected.
@MainActor
final class FeedbackPromptPresenter: NSObject {

    private let application: Application
    private lazy var contactUsHelper = ContactUsHelper(application: application)

    init(application: Application) {
        self.application = application
        super.init()
    }

    /// Presents the sentiment prompt if every gate allows it. Safe to call at
    /// any natural stopping point; it no-ops when ineligible.
    ///
    /// - Parameters:
    ///   - viewController: The controller to present from.
    ///   - canPresent: Caller-owned suppression, evaluated here rather than by the
    ///     caller so that a *delayed* call re-checks its own conditions at fire time.
    ///     `presentedViewController == nil` is the only screen-occupancy check this
    ///     type can make on its own, and it is blind to child view controllers — the
    ///     stop sheet and the map's semi-modal panels are FloatingPanel children, not
    ///     modals. Whoever schedules the call knows what else may have taken the
    ///     screen in the meantime; this is where they say so.
    func presentIfEligible(from viewController: UIViewController, canPresent: () -> Bool = { true }) {
        guard canPresent(),
              application.reviewPromptPolicy.isPromptPending,
              application.promptCoordinator.canShowReviewPrompt(),
              viewController.presentedViewController == nil
        else { return }

        // These three writes only run in the presentation completion handler, which
        // UIKit calls if and only if `present` actually succeeds (e.g. it silently
        // no-ops without calling completion when `viewController` isn't in the window
        // hierarchy or is mid-transition). Recording "shown" before that would burn
        // one of only 3 lifetime asks and the session's single interruption slot for
        // an alert the rider never saw. The completion handler still fires strictly
        // before the alert becomes interactive, so this preserves the property that
        // policy state is written before the rider can possibly answer.
        viewController.present(buildSentimentAlert(from: viewController), animated: true) { [weak self] in
            guard let self else { return }
            self.application.promptCoordinator.noteShown(.review)
            self.application.reviewPromptPolicy.recordPromptPresented()
            self.report(AnalyticsLabels.feedbackPromptShown)
        }
    }

    // MARK: - Step 1

    private func buildSentimentAlert(from viewController: UIViewController) -> UIAlertController {
        let title = String(
            format: OBALoc(
                "feedback_prompt.title",
                value: "Enjoying %@?",
                comment: "Title of the alert asking how the rider likes the app. %@ is the app name."
            ),
            Bundle.main.appName
        )

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        alert.addAction(
            title: OBALoc("feedback_prompt.positive_button", value: "Yes!", comment: "Positive answer to the feedback prompt.")
        ) { [weak self] _ in
            self?.handlePositive()
        }

        alert.addAction(
            title: OBALoc("feedback_prompt.negative_button", value: "Not really", comment: "Negative answer to the feedback prompt.")
        ) { [weak self] _ in
            self?.handleNegative(from: viewController)
        }

        alert.addAction(
            title: OBALoc("feedback_prompt.later_button", value: "Ask Me Later", comment: "Defers the feedback prompt."),
            style: .cancel
        ) { [weak self] _ in
            self?.application.reviewPromptPolicy.recordOutcome(.deferred)
            self?.report(AnalyticsLabels.feedbackDeferred)
        }

        return alert
    }

    // MARK: - Positive branch

    private func handlePositive() {
        application.reviewPromptPolicy.recordOutcome(.positive)
        report(AnalyticsLabels.feedbackPositive)
        Self.openWriteReviewPage()
    }

    /// The App Store's write-a-review URL for the given app ID.
    ///
    /// Split out from `openWriteReviewPage()` so the `?action=write-review` query — the
    /// whole point of the deep link, and silent when wrong, since the App Store happily
    /// opens the plain product page instead — is testable without `UIApplication`.
    static func writeReviewURL(appStoreID: String) -> URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// Opens the App Store's write-a-review page. Shared with the More tab's
    /// "Rate" row so both entry points build the URL identically. Callers report
    /// their own analytics; this only opens the URL.
    static func openWriteReviewPage() {
        guard let appStoreID = Bundle.main.appStoreID,
              let url = writeReviewURL(appStoreID: appStoreID)
        else {
            Logger.warn("No AppStoreID configured; cannot open the write-review page.")
            return
        }

        // The open can fail on a device where the App Store is unavailable — Screen Time
        // restrictions, MDM. The rider sees nothing either way, so leave a trace.
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                Logger.error("Could not open the write-review page: \(url)")
            }
        }
    }

    // MARK: - Negative branch

    private func handleNegative(from viewController: UIViewController) {
        application.reviewPromptPolicy.recordOutcome(.negative)
        report(AnalyticsLabels.feedbackNegative)

        let alert = UIAlertController(
            title: OBALoc("feedback_prompt.negative.title", value: "Sorry about that.", comment: "Title of the follow-up alert after negative feedback."),
            message: OBALoc("feedback_prompt.negative.body", value: "Would you tell us what's wrong? We read every message.", comment: "Body of the follow-up alert after negative feedback."),
            preferredStyle: .alert
        )

        alert.addAction(
            title: OBALoc("feedback_prompt.negative.send_button", value: "Send Feedback", comment: "Opens the feedback email composer.")
        ) { [weak self] _ in
            self?.presentFeedbackEmail(from: viewController)
        }

        alert.addAction(
            title: OBALoc("feedback_prompt.negative.decline_button", value: "No Thanks", comment: "Declines to send feedback."),
            style: .cancel,
            handler: nil
        )

        viewController.present(alert, animated: true)
    }

    private func presentFeedbackEmail(from viewController: UIViewController) {
        // Reported after the guard, not before it. A rider with no Mail account can't
        // open a composer at all, and counting them as "opened" would hide them inside
        // the ordinary opened-then-abandoned population — the one group whose feedback
        // this feature structurally cannot collect is the one worth being able to see.
        guard let composer = contactUsHelper.buildMailComposer(target: .appDevelopers) else {
            report(AnalyticsLabels.feedbackEmailUnavailable)
            viewController.present(contactUsHelper.buildCantSendEmailAlert(target: .appDevelopers), animated: true)
            return
        }

        report(AnalyticsLabels.feedbackEmailOpened)
        composer.mailComposeDelegate = self
        viewController.present(composer, animated: true)
    }

    // MARK: - Analytics

    private func report(_ label: String) {
        application.analytics?.reportEvent(
            pageURL: "app://localhost/feedback",
            label: label,
            value: nil
        )
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension FeedbackPromptPresenter: MFMailComposeViewControllerDelegate {
    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        // Read before `dismiss` starts tearing the presentation down.
        let presenter = controller.presentingViewController
        controller.dismiss(animated: true)

        if result == .sent {
            report(AnalyticsLabels.feedbackEmailSent)
        }

        // This rider already told us something is wrong. Letting a send failure dismiss
        // silently would leave them believing the complaint was delivered when it wasn't.
        // `MoreViewController` surfaces the same delegate's error the same way.
        if let error, let presenter {
            report(AnalyticsLabels.feedbackEmailFailed)
            Task { @MainActor in
                await AlertPresenter.show(error: error, presentingController: presenter)
            }
        }
    }
}
