//
//  StopPageActionPresenter+ProximityAlerts.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import UserNotifications
import OBAKitCore

/// The Stop page's destination proximity alert: setting one, taking it down,
/// and everything that has to be explained to a rider who cannot yet do either.
///
/// Split out of `StopPageActionPresenter` the same way `MapViewController`'s
/// camera and trip-planner flows are — one feature, one file — because the
/// authorization dance around it is longer than the flow itself. The two pieces
/// of in-flight state it needs are stored on the class, since an extension
/// cannot hold stored properties.
///
/// Every decision here is made by ``ProximityAlertOutcome``, which is where they
/// are testable; this only carries them out.
extension StopPageActionPresenter {

    /// How long to wait for an answer before assuming no prompt was raised.
    private static let locationAuthorizationTimeout: Duration = .seconds(10)

    /// Sets or cancels the alert on whichever stop the page currently holds.
    ///
    /// Both menus offer the item before the stop's details have landed — it is
    /// never hidden and never disabled — so the stop is resolved here, at the
    /// moment of the tap, rather than captured when the menu was built.
    func toggleProximityAlert(viewModel: StopViewModel) {
        guard let stop = viewModel.stop else {
            Logger.warn("Ignoring a proximity alert tap for stop \(viewModel.stopID): its details have not loaded yet, so there is no coordinate to watch.")
            return
        }
        toggleProximityAlert(for: stop, viewModel: viewModel)
    }

    /// Sets or cancels this stop's destination proximity alert.
    ///
    /// Two-phase by design: ``ProximityAlertManager/authorizationStep()`` is
    /// asked what is missing *before* the rider is offered anything, and
    /// `createProximityAlert` is only called from `.ready`. The manager's own
    /// documentation is explicit about why — it reports the same shortfalls, but
    /// only once the rider has committed, and in raw statuses that cannot say
    /// whether asking again would raise a prompt or silently do nothing.
    ///
    /// Every decision in here is made by ``ProximityAlertOutcome``, which is
    /// where they are testable; this method only carries them out.
    func toggleProximityAlert(for stop: Stop, viewModel: StopViewModel) {
        guard !isRequestingLocationAuthorization else {
            // The menu has already closed, so there is nothing to disable and
            // nowhere to put a spinner. Dropping the tap is the whole mitigation.
            Logger.info("Ignoring a proximity alert tap for stop \(stop.id): the Always authorization prompt is still outstanding.")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.resolveProximityAlert(for: stop, viewModel: viewModel, canResolveAgain: true)
        }
    }

    /// Asks what is missing, then acts on the answer.
    ///
    /// - Parameter canResolveAgain: `false` on the second pass, so a status that
    ///   keeps moving underneath us costs one retry and a log line rather than
    ///   looping.
    private func resolveProximityAlert(for stop: Stop, viewModel: StopViewModel, canResolveAgain: Bool) async {
        let step = await application.proximityAlertManager.authorizationStep()
        let action = ProximityAlertOutcome.action(forStep: step, existing: viewModel.proximityAlert)
        await perform(action, for: stop, viewModel: viewModel, canResolveAgain: canResolveAgain)
    }

    /// Arms an alert and acts on whatever the manager reports back.
    private func armProximityAlert(for stop: Stop, viewModel: StopViewModel, canResolveAgain: Bool) async {
        let result = await application.proximityAlertManager.createProximityAlert(for: stop)
        let action = ProximityAlertOutcome.action(forResult: result)
        await perform(action, for: stop, viewModel: viewModel, canResolveAgain: canResolveAgain)
    }

    private func perform(
        _ action: ProximityAlertUIAction,
        for stop: Stop,
        viewModel: StopViewModel,
        canResolveAgain: Bool
    ) async {
        switch action {
        case .cancel(let alert):
            application.proximityAlertManager.cancelProximityAlert(alert)
            // The store's change notification refreshes `viewModel.proximityAlert`
            // on its own, which is what flips the menu item back.
            viewModel.signalToast(Self.proximityAlertCancelledText)
        case .arm:
            await armProximityAlert(for: stop, viewModel: viewModel, canResolveAgain: canResolveAgain)
        case .confirmActivated:
            viewModel.signalToast(String(format: Self.proximityAlertSetFormat, stop.name))
        case .requestLocation:
            beginLocationAuthorizationRequest(for: stop)
        case .requestNotifications:
            await requestNotificationAuthorization(for: stop, viewModel: viewModel, canResolveAgain: canResolveAgain)
        case .showSettings(let reason):
            showProximityAlertSettingsAlert(reason: reason)
        case .showLimit(let limit):
            showProximityAlertLimitAlert(limit: limit)
        case .refresh:
            // The menu offered "Alert Me" while one was already set. Correct the
            // page silently: the rider's tap changed nothing, and a confirmation
            // would claim otherwise.
            viewModel.refreshProximityAlert()
        case .resolveAgain:
            guard canResolveAgain else {
                Logger.error("Proximity alert for stop \(stop.id) still reports missing authorization after one re-resolve; giving up on this tap.")
                return
            }
            await resolveProximityAlert(for: stop, viewModel: viewModel, canResolveAgain: false)
        }
    }

    /// Raises the system Always-location prompt, and deliberately stops there.
    ///
    /// The answer arrives through `locationService(_:authorizationStatusChanged:)`
    /// rather than from this call, which returns immediately. PR 4 does not
    /// continue the flow from that callback: the rider has been sent to a system
    /// prompt they may not answer for a while, and arming an alert on their
    /// return is an action they did not take. They tap the item again, the step
    /// now resolves `.ready` — or `.promptForNotifications` — and it proceeds.
    ///
    /// The notification branch does arm inline once granted, and the asymmetry
    /// is the point: that prompt is a blocking sheet that resolves in seconds,
    /// inside the flow the rider just started. This one can be a banner that
    /// sits there indefinitely, and iOS may answer it provisionally and ask
    /// again later.
    private func beginLocationAuthorizationRequest(for stop: Stop) {
        isRequestingLocationAuthorization = true

        // Registered only for the length of the request rather than for the
        // page's life: this is the one moment the presenter cares about location
        // authorization. The service holds delegates weakly, so there is no cycle
        // and nothing to unregister in a `deinit`.
        application.locationService.addDelegate(self)

        locationAuthorizationTimeoutTask?.cancel()
        locationAuthorizationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.locationAuthorizationTimeout)
            } catch {
                // Cancelled by the status callback, which has already released
                // the guard. Clearing it a second time here would be harmless but
                // would also log a timeout that didn't happen.
                return
            }
            guard let self else { return }
            Logger.warn("No location authorization change arrived within \(Self.locationAuthorizationTimeout) of requesting Always for stop \(stop.id); iOS may have raised no prompt. Releasing the proximity alert guard.")
            self.endLocationAuthorizationRequest()
        }

        application.locationService.requestAlwaysAuthorization()
    }

    private func endLocationAuthorizationRequest() {
        isRequestingLocationAuthorization = false
        locationAuthorizationTimeoutTask?.cancel()
        locationAuthorizationTimeoutTask = nil
        application.locationService.removeDelegate(self)
    }

    /// Raises the system notification prompt and, if granted, arms the alert in
    /// the same flow.
    private func requestNotificationAuthorization(for stop: Stop, viewModel: StopViewModel, canResolveAgain: Bool) async {
        let granted: Bool
        do {
            // The `async` form rather than the completion-handler one: it resumes
            // back on this main-actor-isolated method, so the view-model writes
            // below need no hop of their own.
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Logger.error("Requesting notification authorization for a proximity alert on stop \(stop.id) failed: \(error)")
            showProximityAlertSettingsAlert(reason: .notifications)
            return
        }

        guard granted else {
            Logger.info("The rider declined notifications when setting a proximity alert on stop \(stop.id); the alert cannot be delivered.")
            showProximityAlertSettingsAlert(reason: .notifications)
            return
        }

        await armProximityAlert(for: stop, viewModel: viewModel, canResolveAgain: canResolveAgain)
    }

    // MARK: - Proximity Alert Alerts

    /// Sends a rider whose permissions can no longer be asked for to Settings.
    ///
    /// Same shape as ``showAlarmPermissionDeniedAlert(onPresented:)``: Cancel
    /// plus Open Settings, and a body that names the app through
    /// `Bundle.main.appName` rather than a literal — this is a white-label
    /// framework and the alert ships in every agency's build.
    func showProximityAlertSettingsAlert(reason: ProximityAlertSettingsReason) {
        let alert = UIAlertController(
            title: reason.alertTitle,
            message: reason.alertMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Self.openSettingsTitle, style: .default) { [weak self] _ in
            guard let self, let url = URL(string: UIApplication.openSettingsURLString) else { return }
            self.application.open(url, options: [:], completionHandler: nil)
        })
        presentationHost(for: "proximity alert settings guidance")?.present(alert, animated: true)
    }

    /// Tells a rider that iOS will not monitor another region for them.
    ///
    /// Informational, with no action beyond dismissing it: there is no screen
    /// listing a rider's alerts yet, so there is nowhere for a "Manage Alerts"
    /// button to go, and inventing one is a different change.
    func showProximityAlertLimitAlert(limit: Int) {
        let alert = UIAlertController(
            title: OBALoc(
                "stop_page.proximity_alert.region_limit.title",
                value: "Too Many Alerts",
                comment: "Title of the alert shown when iOS will not monitor another region because the app is already at its limit."
            ),
            message: String(
                format: OBALoc(
                    "stop_page.proximity_alert.region_limit.message_fmt",
                    value: "iOS lets %1$@ watch for %2$d places at once. Cancel one to add another.",
                    comment: "Body of the alert shown when the app is already monitoring every region iOS allows. %1$@ is the app name and %2$d is the number of regions."
                ),
                Bundle.main.appName,
                limit
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .cancel))
        presentationHost(for: "proximity alert region limit")?.present(alert, animated: true)
    }

    private static var openSettingsTitle: String {
        OBALoc(
            "stop_page.proximity_alert.open_settings",
            value: "Open Settings",
            comment: "Button that opens the system Settings app so the rider can grant what a nearby alert needs."
        )
    }

    private static var proximityAlertSetFormat: String {
        OBALoc(
            "stop_page.proximity_alert.toast.set_fmt",
            value: "We'll let you know when you're near %@",
            comment: "Toast confirming a nearby alert was set. %@ is the name of the stop."
        )
    }

    private static var proximityAlertCancelledText: String {
        OBALoc(
            "stop_page.proximity_alert.toast.cancelled",
            value: "Nearby alert cancelled",
            comment: "Toast confirming the rider's nearby alert for this stop was taken down."
        )
    }
}

// MARK: - LocationServiceDelegate

extension StopPageActionPresenter: LocationServiceDelegate {
    /// Releases the in-flight guard as soon as the rider answers the Always
    /// prompt — in either direction. The flow is deliberately not continued from
    /// here; see ``beginLocationAuthorizationRequest(for:)``.
    ///
    /// Registered only while a request is outstanding, so this fires for one
    /// answer and the presenter then stops listening.
    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        Logger.info("Location authorization answered with \(status) while a proximity alert request was outstanding.")
        endLocationAuthorizationRequest()
    }
}
