//
//  OnboardingFlowController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// UIKit entry point for the onboarding flow. A plain `UIViewController` embedding a
/// `UIHostingController` child, because `UIHostingController` subclasses can't be exposed
/// to Objective-C.
///
/// Usage (see `OBARootInterfaceLauncher`, called from each app delegate's
/// `applicationReloadRootInterface:`): call ``evaluate(application:completion:)``;
/// if the completion hands you a controller, set its ``onFinished`` block and install
/// it as the window's root view controller.
@objc(OBAOnboardingFlowController)
public class OnboardingFlowController: UIViewController {
    /// Called on the main queue when the user completes the last step. Guaranteed to fire
    /// at most once, even if the underlying flow view invokes its completion more than once
    /// (e.g. a double-tap on the final screen's button before dismissal).
    @objc public var onFinished: (() -> Void)?

    private var didFireFinished = false

    private let application: Application
    private let steps: [OnboardingStep]
    private let store: OnboardingStepStore

    private static var testOnboarding: Bool {
        #if DEBUG
        let envVar = ProcessInfo.processInfo.environment["TEST_ONBOARDING"] ?? "0"
        return (envVar as NSString).boolValue
        #else
        return false
        #endif
    }

    /// Computes the onboarding flow for this launch and calls back on the main queue with
    /// a ready-to-present controller, or `nil` if no onboarding is needed.
    ///
    /// Also performs the one-time existing-user backfill: users with a selected region but
    /// no seen-step record are marked as having seen the pre-registry steps, so the only
    /// seen-tracked steps they can match are ones added after the registry shipped
    /// (e.g. notifications). Migration ignores the seen store and re-prompts until it succeeds.
    @objc public static func evaluate(application: Application, completion: @escaping (OnboardingFlowController?) -> Void) {
        Task { @MainActor in
            let store = OnboardingStepStore(userDefaults: application.userDefaults)
            store.backfillIfNeeded(hasCurrentRegion: application.regionsService.currentRegion != nil)

            let environment = await OnboardingEnvironment.current(application: application)
            var flow = OnboardingRegistry.flow(environment: environment, store: store)

            if testOnboarding {
                flow = OnboardingRegistry.steps
            }

            // Field-diagnosable breadcrumb: the window has no root VC until this completes.
            Logger.info("Onboarding flow computed: \(flow.map(\.id.rawValue))")

            guard !flow.isEmpty else {
                completion(nil)
                return
            }

            completion(OnboardingFlowController(application: application, steps: flow, store: store))
        }
    }

    @MainActor
    init(application: Application, steps: [OnboardingStep], store: OnboardingStepStore) {
        precondition(!steps.isEmpty, "OnboardingFlowController requires a non-empty flow")
        self.application = application
        self.steps = steps
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let flowView = OnboardingFlowView(application: application, steps: steps, store: store) { [weak self] in
            self?.fireOnFinishedOnce()
        }

        let host = UIHostingController(rootView: flowView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func fireOnFinishedOnce() {
        guard !didFireFinished else { return }
        didFireFinished = true
        onFinished?()
    }
}
