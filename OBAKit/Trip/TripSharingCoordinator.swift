//
//  TripSharingCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Drives the trip-sharing flow: presents the destination stop picker and, once
/// the user picks a stop (or opts to share without one), swaps it for the system
/// share sheet with the encoded deep link. Shared by the legacy
/// `StopViewController` and the redesigned `StopPageViewController` so the flow
/// exists in exactly one place.
@MainActor
final class TripSharingCoordinator: NSObject, DestinationStopPickerDelegate {

    private let application: Application

    /// Held weakly: if the presenting screen goes away mid-flow there is no UI
    /// left to drive, so every step simply ends.
    private weak var presenter: UIViewController?

    /// - Parameters:
    ///   - application: The application object.
    ///   - presenter: The view controller the picker, share sheet, and error
    ///     alert are presented from.
    init(application: Application, presenter: UIViewController) {
        self.application = application
        self.presenter = presenter
    }

    /// Entry point: presents the destination stop picker for `arrivalDeparture`.
    func start(arrivalDeparture: ArrivalDeparture) {
        guard let presenter else { return }
        let picker = DestinationStopPickerController(
            application: application,
            arrivalDeparture: arrivalDeparture
        )
        picker.delegate = self
        let nav = application.viewRouter.buildNavigation(controller: picker)
        application.viewRouter.present(nav, from: presenter, isModal: true)
    }

    /// Shows the shared "Unable to Share" alert. Exposed so entry points can
    /// report failures that occur before the picker is presented (e.g. a stale
    /// view model with no matching `ArrivalDeparture`).
    func presentShareError() {
        let alert = UIAlertController(
            title: OBALoc("trip_sharing.share_error.title", value: "Unable to Share", comment: "Alert title when trip sharing fails."),
            message: OBALoc("trip_sharing.share_error.message", value: "Something went wrong while preparing the trip link. Please try again.", comment: "Alert message when trip sharing fails."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .default))
        presenter?.present(alert, animated: true)
    }

    // MARK: - DestinationStopPickerDelegate

    func destinationStopPicker(
        _ controller: DestinationStopPickerController,
        didSelectStop stopTime: TripStopTime
    ) {
        shareTrip(arrivalDeparture: controller.arrivalDeparture, destinationStopID: stopTime.stopID)
    }

    func destinationStopPickerDidSkipDestination(_ controller: DestinationStopPickerController) {
        shareTrip(arrivalDeparture: controller.arrivalDeparture, destinationStopID: nil)
    }

    func destinationStopPickerDidCancel(_ controller: DestinationStopPickerController) {
        presenter?.dismiss(animated: true)
    }

    // MARK: - Share Sheet

    /// Dismisses the picker, encodes the share URL (with an optional destination
    /// stop), and presents the share sheet.
    private func shareTrip(arrivalDeparture: ArrivalDeparture, destinationStopID: StopID?) {
        guard let presenter else { return }
        presenter.dismiss(animated: true) { [weak self] in
            guard let self, let presenter = self.presenter else { return }
            guard
                let region = self.application.currentRegion,
                let appLinksRouter = self.application.appLinksRouter
            else {
                Logger.error("Missing region or appLinksRouter for trip sharing. tripID: \(arrivalDeparture.tripID), stopID: \(arrivalDeparture.stopID)")
                self.presentShareError()
                return
            }

            guard let url = appLinksRouter.encode(
                arrivalDeparture: arrivalDeparture,
                region: region,
                destinationStopID: destinationStopID
            ) else {
                Logger.error("Failed to encode trip sharing URL. tripID: \(arrivalDeparture.tripID), destinationStopID: \(destinationStopID ?? "none")")
                self.presentShareError()
                return
            }

            let activityController = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            // iPad support: without an anchored popover, presenting a share
            // sheet on iPad throws at runtime.
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            // Use presenter.present because when using application.viewRouter.present(:_),
            // it disables UIActivityViewController's "tap anywhere to dismiss".
            presenter.present(activityController, animated: true)
        }
    }
}
