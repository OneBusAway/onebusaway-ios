//
//  StopViewController+LiveActivity.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import OBAKitCore
import UIKit

extension StopViewController {

    // MARK: - Section

    /// Returns a "Stop Live Activity" row only when there is an active activity for this stop.
    /// Shown between the map header and service alerts — per spec.
    /// Starting is handled via the `...` pulldown menu and arrival row swipe/context actions.
    @available(iOS 16.2, *)
    var stopLiveActivitySection: OBAListViewSection? {
        guard application.liveActivityManager.isSupported else { return nil }
        guard let item = activeActivityItemForCurrentStop() else { return nil }
        return listViewSection(for: .liveActivity, title: nil, items: [item])
    }

    /// Returns a list section with a Start or Stop Live Activity button.
    ///
    /// Shown when:
    /// - The stop was opened from a trip bookmark (`bookmarkContext` is set), OR
    /// - There is already an active Live Activity for any arrival at this stop.
    @available(iOS 16.2, *)
    var liveActivitySection: OBAListViewSection? {
        guard application.liveActivityManager.isSupported else { return nil }

        // Case 1: opened from a bookmark — show start/stop for that specific trip.
        if let bookmark = bookmarkContext,
           let routeShortName = bookmark.routeShortName,
           let tripHeadsign = bookmark.tripHeadsign {

            let hasActive = application.liveActivityManager.hasActiveActivity(
                stopID: stopID,
                regionIdentifier: bookmark.regionIdentifier,
                routeShortName: routeShortName,
                tripHeadsign: tripHeadsign
            )

            let item = LiveActivityListItem(
                id: "live_activity_\(stopID)_\(routeShortName)",
                action: hasActive ? .stop : .start
            ) { [weak self] _ in
                guard let self else { return }
                if hasActive {
                    self.stopLiveActivity(
                        routeShortName: routeShortName,
                        tripHeadsign: tripHeadsign,
                        regionIdentifier: bookmark.regionIdentifier
                    )
                } else {
                    self.startLiveActivity(for: bookmark)
                }
            }
            return listViewSection(for: .liveActivity, title: nil, items: [item])
        }

        // Case 2: active activity for this stop — show Stop button.
        if let activeItem = activeActivityItemForCurrentStop() {
            return listViewSection(for: .liveActivity, title: nil, items: [activeItem])
        }

        // Case 3: no bookmark, no active activity — show Start button whenever
        // the stop is loaded so the user can track from any stop page.
        // The bulletin will use the best available arrival at tap time.
        if stopArrivals != nil, let region = application.currentRegion {
            let item = LiveActivityListItem(
                id: "live_activity_start_\(stopID)",
                action: .start
            ) { [weak self] _ in
                guard let self,
                      let stop = self.stop,
                      let arrivalDeparture = self.stopArrivals?.arrivalsAndDepartures.first(where: {
                          $0.arrivalDepartureMinutes >= 0
                      }) ?? self.stopArrivals?.arrivalsAndDepartures.first
                else { return }

                let tempBookmark = Bookmark(
                    name: arrivalDeparture.routeShortName,
                    regionIdentifier: region.regionIdentifier,
                    arrivalDeparture: arrivalDeparture,
                    stop: stop
                )
                self.startLiveActivity(bookmark: tempBookmark, arrivalDeparture: arrivalDeparture)
            }
            return listViewSection(for: .liveActivity, title: nil, items: [item])
        }

        return nil
    }

    // MARK: - Update

    /// Called from `stopArrivals.didSet` — pushes fresh arrival times to any active Live Activity for this stop.
    @available(iOS 16.2, *)
    func updateLiveActivitiesIfNeeded(from stopArrivals: StopArrivals) {
        guard application.liveActivityManager.isSupported else { return }

        // Find all active activities for this stop and update them with the latest arrival data.
        for activity in Activity<TransitArrivalAttributes>.activities where activity.activityState == .active {
            let attrs = activity.attributes
            guard attrs.stopID == stopID else { continue }

            // Find the matching arrival departure for this activity's route/headsign.
            let arrivalDeparture = stopArrivals.arrivalsAndDepartures.first {
                $0.routeShortName == attrs.routeShortName &&
                $0.tripHeadsign == attrs.tripHeadsign &&
                $0.arrivalDepartureMinutes >= -1
            } ?? stopArrivals.arrivalsAndDepartures.first {
                $0.routeShortName == attrs.routeShortName
            }

            guard let arrivalDeparture else { continue }

            Task {
                await application.liveActivityManager.updateActivities(
                    stopID: attrs.stopID,
                    regionIdentifier: attrs.regionIdentifier,
                    routeShortName: attrs.routeShortName,
                    tripHeadsign: attrs.tripHeadsign,
                    arrivalDeparture: arrivalDeparture
                )
            }
        }
    }

    // MARK: - Start

    /// Presents the `LiveActivityBuilder` bulletin for the given bookmark.
    @available(iOS 16.2, *)
    func startLiveActivity(for bookmark: Bookmark) {
        guard let arrivalDeparture = bestArrivalDeparture(for: bookmark) else { return }
        startLiveActivity(bookmark: bookmark, arrivalDeparture: arrivalDeparture)
    }

    /// Starts a Live Activity from an `ArrivalDepartureItem` swipe/context menu action.
    /// Creates a temporary bookmark-like object from the arrival data.
    @available(iOS 16.2, *)
    func startLiveActivityFromArrivalItem(_ viewModel: ArrivalDepartureItem) {
        guard let arrivalDeparture = arrivalDeparture(forViewModel: viewModel),
              let stop = self.stop,
              let region = application.currentRegion
        else { return }

        // Build a temporary bookmark from the arrival departure so we can reuse LiveActivityBuilder
        let tempBookmark = Bookmark(
            name: viewModel.name,
            regionIdentifier: region.regionIdentifier,
            arrivalDeparture: arrivalDeparture,
            stop: stop
        )
        startLiveActivity(bookmark: tempBookmark, arrivalDeparture: arrivalDeparture)
    }

    func startLiveActivity(bookmark: Bookmark, arrivalDeparture: ArrivalDeparture) {
        let builder = LiveActivityBuilder(
            bookmark: bookmark,
            arrivalDeparture: arrivalDeparture,
            manager: application.liveActivityManager
        )
        builder.onActivityStarted = { [weak self] in
            self?.listView.applyData()
        }
        liveActivityBuilder = builder
        builder.showBulletin(above: self)
    }
    // MARK: - Stop

    @available(iOS 16.2, *)
    func stopLiveActivity(routeShortName: String, tripHeadsign: String, regionIdentifier: Int) {
        Task {
            await application.liveActivityManager.stopActivities(
                stopID: stopID,
                regionIdentifier: regionIdentifier,
                routeShortName: routeShortName,
                tripHeadsign: tripHeadsign
            )
            await MainActor.run { self.listView.applyData() }
        }
    }

    // MARK: - Helpers

    /// Finds the best upcoming `ArrivalDeparture` for the given bookmark.
    @available(iOS 16.2, *)
    func bestArrivalDeparture(for bookmark: Bookmark) -> ArrivalDeparture? {
        stopArrivals?.arrivalsAndDepartures.first {
            $0.routeID == bookmark.routeID &&
            $0.tripHeadsign == bookmark.tripHeadsign &&
            $0.arrivalDepartureMinutes >= 0
        } ?? stopArrivals?.arrivalsAndDepartures.first {
            $0.routeID == bookmark.routeID
        }
    }

    /// Returns a Stop Live Activity list item if there is an active activity for any arrival at this stop.
    @available(iOS 16.2, *)
    private func activeActivityItemForCurrentStop() -> LiveActivityListItem? {
        // Find the first active activity whose stopID matches ours — no need to check currentRegion
        // since the regionIdentifier is already baked into the activity attributes.
        let active = Activity<TransitArrivalAttributes>.activities.first {
            $0.attributes.stopID == stopID &&
            $0.activityState == .active
        }
        guard let active else { return nil }

        let routeShortName = active.attributes.routeShortName
        let tripHeadsign = active.attributes.tripHeadsign
        let regionIdentifier = active.attributes.regionIdentifier

        return LiveActivityListItem(
            id: "live_activity_stop_\(stopID)",
            action: .stop
        ) { [weak self] _ in
            guard let self else { return }
            self.stopLiveActivity(
                routeShortName: routeShortName,
                tripHeadsign: tripHeadsign,
                regionIdentifier: regionIdentifier
            )
        }
    }
}

// MARK: - Associated Object for LiveActivityBuilder retention

private var liveActivityBuilderKey: UInt8 = 0

@available(iOS 16.2, *)
extension StopViewController {
    fileprivate var liveActivityBuilder: LiveActivityBuilder? {
        get { objc_getAssociatedObject(self, &liveActivityBuilderKey) as? LiveActivityBuilder }
        set { objc_setAssociatedObject(self, &liveActivityBuilderKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - File Menu (Live Activity entry point)

extension StopViewController {
    /// Builds the "File" section of the stop page's pulldown menu.
    /// Includes "Add Bookmark", "Start/Stop Live Activity" (iOS 16.2+), and "Service Alerts".
    func buildFileMenu() -> UIMenu {
        let bookmarkAction = UIAction(title: Strings.addBookmark, image: UIImage(systemName: "bookmark")) { [unowned self] action in
            self.addBookmark(sender: action)
        }

        let alertsAction = UIAction(title: Strings.serviceAlerts, image: UIImage(systemName: "exclamationmark.circle")) { [unowned self] _ in
            let controller = ServiceAlertListController(application: self.application, serviceAlerts: self.stopArrivals?.serviceAlerts ?? [])
            self.application.viewRouter.navigate(to: controller, from: self)
        }
        if (stopArrivals?.serviceAlerts ?? []).isEmpty {
            alertsAction.attributes = .disabled
        }

        var children: [UIMenuElement] = [bookmarkAction]

        if #available(iOS 16.2, *), application.liveActivityManager.isSupported, stopArrivals != nil {
            // Only offer Start from the menu — Stop is handled by the list row on the stop page (per spec).
            let hasActive = Activity<TransitArrivalAttributes>.activities.contains {
                $0.attributes.stopID == stopID && $0.activityState == .active
            }
            // Don't show Start if already active — the list row handles stopping.
            if !hasActive {
                let liveActivityAction = UIAction(
                    title: OBALoc("live_activity.action.start", value: "Start Live Activity", comment: "Context menu action to start a Live Activity"),
                    image: UIImage(systemName: "livephoto")
                ) { [weak self] _ in
                    guard let self,
                          let stop = self.stop,
                          let region = self.application.currentRegion,
                          let arrivalDeparture = self.stopArrivals?.arrivalsAndDepartures.first(where: {
                              $0.arrivalDepartureMinutes >= 0
                          }) ?? self.stopArrivals?.arrivalsAndDepartures.first
                    else { return }

                    let tempBookmark = Bookmark(
                        name: arrivalDeparture.routeShortName,
                        regionIdentifier: region.regionIdentifier,
                        arrivalDeparture: arrivalDeparture,
                        stop: stop
                    )
                    self.startLiveActivity(bookmark: tempBookmark, arrivalDeparture: arrivalDeparture)
                }
                children.append(liveActivityAction)
            }
        }

        children.append(alertsAction)
        return UIMenu(title: "File", options: .displayInline, children: children)
    }
}

// MARK: - ArrivalDepartureItem + Live Activity

extension ArrivalDepartureItem {
    /// Attaches a Live Activity swipe/context action if supported, returning self for chaining.
    func withLiveActivityAction(from vc: StopViewController) -> ArrivalDepartureItem {
        var copy = self
        if #available(iOS 16.2, *), vc.application.liveActivityManager.isSupported {
            copy.liveActivityAction = { [weak vc] item in
                vc?.startLiveActivityFromArrivalItem(item)
            }
        }
        return copy
    }
}
