//
//  TripPlanEmptyFallback.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OTPKit

/// R11 (spec 3.8): when the planner comes back empty (an OTP error or zero
/// itineraries), probe both ends and dock the on-demand options. Shared by the
/// classic map and the map panel, which differ only in how they uncover the card.
///
/// Listens between `start` and `stop`, for exactly as long as one planner is open.
/// A new plan with itineraries clears the card, and a re-plan cancels the probe
/// still running for the last one, so a late answer can't show a card for
/// endpoints the rider has left.
///
/// Selector observers rather than the block form: the center holds them weakly and
/// drops them on dealloc, so there is no token for a `deinit` to remove off the main
/// actor. OTPKit posts both notifications from its main-actor view model.
final class TripPlanEmptyFallback: NSObject {
    private let probeController: OnDemandProbeController
    private let notificationCenter: NotificationCenter

    /// Called after every change to the dock's planner state; `true` when a card
    /// has just been shown, so the surface can move its planner out of the way.
    var onChange: (_ isShowingCard: Bool) -> Void = { _ in }

    /// The endpoints the planner opened with, used when OTPKit's notification
    /// carries none (`TripPlanEmptyEndpoints`).
    private(set) var origin: CLLocationCoordinate2D?
    private(set) var destination: CLLocationCoordinate2D?

    /// The probe for the latest empty plan, if one is running.
    private(set) var task: Task<Void, Never>?

    private(set) var isListening = false

    init(probeController: OnDemandProbeController, notificationCenter: NotificationCenter) {
        self.probeController = probeController
        self.notificationCenter = notificationCenter
        super.init()
    }

    /// A planner opened. Replaces whatever the previous one left behind.
    func start(origin: CLLocationCoordinate2D?, destination: CLLocationCoordinate2D?) {
        stop()
        self.origin = origin
        self.destination = destination
        notificationCenter.addObserver(self, selector: #selector(itinerariesUpdated), name: Notifications.itinerariesUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(tripPlanEmpty(_:)), name: Notifications.tripPlanEmpty, object: nil)
        isListening = true
    }

    /// The planner closed. Nothing it planned may outlive it.
    func stop() {
        if isListening {
            notificationCenter.removeObserver(self, name: Notifications.itinerariesUpdated, object: nil)
            notificationCenter.removeObserver(self, name: Notifications.tripPlanEmpty, object: nil)
            isListening = false
        }
        task?.cancel()
        task = nil
        origin = nil
        destination = nil
        clear()
    }

    @objc private func itinerariesUpdated() {
        task?.cancel()
        task = nil
        clear()
    }

    @objc private func tripPlanEmpty(_ note: Notification) {
        task?.cancel()
        // An OTP error posts no `itinerariesUpdated`, so nothing else removes a
        // card from an earlier empty plan; one for other endpoints must not
        // outlive a re-plan whose own card can't be built.
        guard let endpoints = TripPlanEmptyEndpoints.resolve(
            userInfo: note.userInfo,
            fallbackOrigin: origin,
            fallbackDestination: destination
        ) else {
            task = nil
            clear()
            return
        }

        task = Task { [weak self, probeController] in
            let result = await probeController.plannerResult(origin: endpoints.origin, destination: endpoints.destination)
            guard !Task.isCancelled, let self else { return }
            guard let result else {
                clear()
                return
            }
            probeController.showPlanner(result)
            onChange(true)
        }
    }

    private func clear() {
        probeController.clearPlanner()
        onChange(false)
    }
}
