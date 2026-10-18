//
//  ErrorPresenter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MessageUI
import SwiftUI
import UIKit
import OBAKitCore

/// Shows an ``ErrorToastView`` for an `ErrorReport` and, from its Details
/// button, the ``ProblemDetailsView`` (#1582).
///
/// Both live in a window of their own rather than being presented from
/// `topViewController`: that walk lands inside the map-panel home sheet's
/// hosting controller, which is held to its current detent and squeezes
/// anything presented from it (see `BulletinOverlayWindow`). The window passes
/// through every touch that misses the toast, so the screen underneath stays
/// usable while the toast is up.
@MainActor
final class ErrorPresenter: NSObject {

    /// How long a toast stays up. VoiceOver users get longer; see
    /// `ToastManager.dwell(for:isVoiceOverRunning:)`.
    static let toastDuration: TimeInterval = 4

    private var window: PassthroughWindow?
    private var toastHost: UIHostingController<ErrorToastView>?
    private var dismissTask: Task<Void, Never>?
    private weak var previousKeyWindow: UIWindow?

    /// The report on screen, as a toast or a details page.
    private var currentReport: ErrorReport?

    /// `true` while the details page is up.
    private var isShowingDetails = false

    /// Whether `report` should replace what's on screen.
    ///
    /// The same failure tends to arrive in bursts — `BookmarkDataLoader` runs one
    /// fetch, and one `displayError`, per bookmark (#1421) — so a report that
    /// says the same thing as the one already up is dropped. A report that
    /// would cover an open details page is dropped too: the rider is reading.
    static func shouldPresent(_ report: ErrorReport, current: ErrorReport?, isShowingDetails: Bool) -> Bool {
        guard !report.isSilent, !isShowingDetails else { return false }
        guard let current else { return true }
        return current.title != report.title || current.summary != report.summary
    }

    func present(_ report: ErrorReport, in scene: UIWindowScene) {
        // A repeat aimed at another window (iPad) isn't a repeat for the rider
        // looking at that one.
        let current = window?.windowScene === scene ? currentReport : nil
        guard Self.shouldPresent(report, current: current, isShowingDetails: isShowingDetails) else { return }

        currentReport = report
        let window = installWindowIfNeeded(in: scene)
        showToast(ErrorToast(report: report), in: window)
        AccessibilityAnnouncement.post("\(report.title). \(report.summary)")
        scheduleDismissal()
    }

    // MARK: - Toast

    private func showToast(_ toast: ErrorToast, in window: PassthroughWindow) {
        let view = ErrorToastView(
            toast: toast,
            onAction: { [weak self] in self?.performAction() },
            onDismiss: { [weak self] in self?.dismissToast() }
        )

        if let toastHost {
            toastHost.rootView = view
            return
        }

        guard let root = window.rootViewController else { return }
        let host = UIHostingController(rootView: view)
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        root.addChild(host)
        root.view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            host.view.trailingAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            // The keyboard guide sits on the safe area when there's no keyboard,
            // and keeps the toast visible above it when there is.
            host.view.bottomAnchor.constraint(equalTo: root.view.keyboardLayoutGuide.topAnchor, constant: -8)
        ])
        host.didMove(toParent: root)
        toastHost = host

        host.view.alpha = 0
        host.view.transform = CGAffineTransform(translationX: 0, y: 40)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            host.view.alpha = 1
            host.view.transform = .identity
        }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        let dwell = ToastManager.dwell(for: Self.toastDuration, isVoiceOverRunning: UIAccessibility.isVoiceOverRunning)
        dismissTask = Task { [weak self] in
            // Hold the toast while its scene is inactive (launch, Control
            // Center pulled down), so the dwell starts when the rider can see it.
            while self?.window?.windowScene?.activationState == .foregroundInactive {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }

    private func dismissToast() {
        dismissTask?.cancel()
        guard let host = toastHost else { return }
        toastHost = nil
        UIView.animate(withDuration: 0.25, animations: {
            host.view.alpha = 0
            host.view.transform = CGAffineTransform(translationX: 0, y: 40)
        }, completion: { [weak self] _ in
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            self?.tearDownIfIdle()
        })
    }

    // MARK: - Actions

    private func performAction() {
        guard let report = currentReport else { return }
        switch report.action {
        case .details:
            showDetails(for: report)
        case .openSettings:
            dismissToast()
            openSettings()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func showDetails(for report: ErrorReport) {
        guard let window, let root = window.rootViewController else { return }
        dismissToast()
        isShowingDetails = true

        // Key while the page is up, so it gets focus and VoiceOver lands in it.
        previousKeyWindow = window.windowScene?.windows.first { $0.isKeyWindow && $0 !== window }
        window.makeKey()

        let details = UIHostingController(rootView: ProblemDetailsView(
            report: report,
            onDone: { [weak self] in self?.dismissDetails() },
            onContactSupport: { [weak self] in self?.contactSupport(about: report) }
        ))
        details.presentationController?.delegate = self
        root.present(details, animated: true)
    }

    private func dismissDetails() {
        window?.rootViewController?.dismiss(animated: true) { [weak self] in
            self?.detailsDidDismiss()
        }
    }

    private func detailsDidDismiss() {
        isShowingDetails = false
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
        tearDownIfIdle()
    }

    private func contactSupport(about report: ErrorReport) {
        let email = ContactUsHelper.appDevelopersEmail
        let subject = String(format: ErrorStrings.supportEmailSubjectFmt, Bundle.main.appName, report.reference)

        guard
            MFMailComposeViewController.canSendMail(),
            let presenter = window?.rootViewController?.presentedViewController
        else {
            // No Mail account: hand off to whatever mail app handles mailto.
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = email
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: report.shareText)
            ]
            if let url = components.url {
                UIApplication.shared.open(url)
            }
            return
        }

        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        composer.setToRecipients([email])
        composer.setSubject(subject)
        composer.setMessageBody(report.shareText, isHTML: false)
        presenter.present(composer, animated: true)
    }

    // MARK: - Window

    private func installWindowIfNeeded(in scene: UIWindowScene) -> PassthroughWindow {
        if let window, window.windowScene === scene {
            return window
        }
        // Moving to another scene: the toast up in the old window goes with it,
        // or `showToast` would update that hidden host instead of showing one here.
        window?.isHidden = true
        toastHost = nil

        let window = PassthroughWindow(windowScene: scene)
        // Above the app and its sheets, below system alerts.
        window.windowLevel = .alert - 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view = PassthroughView()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        window.isHidden = false
        self.window = window
        return window
    }

    private func tearDownIfIdle() {
        guard toastHost == nil, !isShowingDetails else { return }
        currentReport = nil
        window?.isHidden = true
        window = nil
    }
}

// MARK: - Delegates

extension ErrorPresenter: UIAdaptivePresentationControllerDelegate {
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Swiped down rather than tapping Done.
        MainActor.assumeIsolated { detailsDidDismiss() }
    }
}

extension ErrorPresenter: MFMailComposeViewControllerDelegate {
    nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        MainActor.assumeIsolated { controller.dismiss(animated: true) }
    }
}

// MARK: - Target Scene

extension UIApplication {
    /// The scene an error toast goes to: `bulletinTargetScene`, or failing that
    /// a foreground-inactive app scene (at launch, or with Control Center pulled
    /// down), so an error arriving then still reaches the rider.
    var errorToastTargetScene: UIWindowScene? {
        bulletinTargetScene ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundInactive && $0.session.role == .windowApplication }
    }
}

// MARK: - Passthrough

// Both levels need the override: with the root view passing a touch through,
// the window would otherwise return itself and swallow it.

/// A window that only claims touches landing on one of its subviews.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// A root view that is transparent to touches; its subviews are not.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
