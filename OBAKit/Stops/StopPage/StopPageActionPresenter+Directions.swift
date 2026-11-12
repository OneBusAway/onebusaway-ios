//
//  StopPageActionPresenter+Directions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import OBAKitCore
import OTPKit

/// Getting to and from the stop: walking directions in a maps app, and the
/// trip planner.
extension StopPageActionPresenter {

    /// One available maps app opens directly; more than one presents an action
    /// sheet to disambiguate.
    func showWalkingDirections(coordinate: CLLocationCoordinate2D) {
        var options: [(title: String, url: URL)] = []

        if let appleMapsURL = AppInterop.appleMapsWalkingDirectionsURL(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_apple", value: "Walking Directions (Apple Maps)", comment: "Button that launches Apple's maps.app with walking directions to this stop"),
                appleMapsURL
            ))
        }

        #if !targetEnvironment(simulator)
        if let googleMapsURL = AppInterop.googleMapsWalkingDirectionsURL(coordinate: coordinate),
           googleMapsAvailable(coordinate: coordinate) {
            options.append((
                OBALoc("stops_controller.walking_directions_google", value: "Walking Directions (Google Maps)", comment: "Button that launches Google Maps with walking directions to this stop"),
                googleMapsURL
            ))
        }
        #endif

        guard let first = options.first else { return }

        if options.count == 1 {
            application.open(first.url, options: [:], completionHandler: nil)
            return
        }

        let sheet = UIAlertController(
            title: OBALoc("stops_controller.walking_directions", value: "Walking Directions", comment: "Button that launches a maps app with walking directions to this stop"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for option in options {
            sheet.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in
                self?.application.open(option.url, options: [:], completionHandler: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: Strings.cancel, style: .cancel))
        present(actionSheet: sheet)
    }

    func makeTripPlannerClosure(_ action: StopTripPlannerAction, viewModel: StopViewModel) -> () -> Void {
        return { [weak self] in
            guard let stop = viewModel.stop else { return }
            self?.showTripPlanner(action: action, stop: stop)
        }
    }

    func makePillDirections(viewModel: StopViewModel, tripPlannerAvailable: Bool) -> StopPillDirections {
        StopPillDirections(tripPlannerAvailable: tripPlannerAvailable) { [weak self] behavior in
            guard let stop = viewModel.stop else { return }
            self?.showDirections(behavior, stop: stop)
        }
    }

    /// A tap on the header's walk or bike pill (#1546). With a trip planner it asks
    /// before leaving the stop page; "walk" and "bike" read as information first,
    /// and the planner replaces the whole screen.
    func showDirections(_ behavior: StopDirectionsPill.Behavior, stop: Stop) {
        switch behavior {
        case .askThenPlanTrip(let pill):
            guard let host = presentationHost(for: "directions prompt") else { return }
            let prompt = UIAlertController(title: StopDirectionsPill.promptTitle, message: nil, preferredStyle: .alert)
            prompt.addAction(UIAlertAction(title: StopTripPlannerAction.directionsToHereTitle, style: .default) { [weak self] _ in
                self?.showTripPlanner(action: .directionsToStop, stop: stop, mode: pill.mode)
            })
            prompt.addAction(.cancelAction)
            host.present(prompt, animated: true)
        case .openMapsWalkingDirections:
            showWalkingDirections(coordinate: stop.coordinate)
        }
    }

    /// Opens the trip planner with this stop as origin or destination, and `mode`
    /// chosen when given: the host's own planner when it has one, otherwise the
    /// classic map tab's. Shared by the pushed Stop page and the map sheet.
    func showTripPlanner(action: StopTripPlannerAction, stop: Stop, mode: TransportMode? = nil) {
        if let onShowTripPlannerInSheet {
            onShowTripPlannerInSheet(action, stop, mode)
            return
        }
        StopTripPlannerAction.present(action, stop: stop, mode: mode, application: application, from: presentingController())
    }
}
