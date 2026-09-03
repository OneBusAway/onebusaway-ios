//
//  BookmarkActions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import ActivityKit
import OBAKitCore

/// Bookmark row actions shared by the Bookmarks tab (`BookmarksViewController`)
/// and the Bookmarks index sheet (`BookmarksSheetView`).
///
/// Holds no view model and presents nothing: arrivals are passed in, deletion is
/// performed by the caller's view model, and the bookmark editor is *built* here
/// but presented by whoever asked for it. That's what lets a `UIViewController`
/// and a SwiftUI view share one implementation — the tab presents via
/// `viewRouter`, the sheet via `.sheet(item:)`.
@MainActor
final class BookmarkActions {

    /// What `startLiveActivity` did. Failure is returned rather than alerted:
    /// `showLiveActivityErrorAlert()` is a `UIViewController` extension, so the
    /// tab raises a `UIAlertController` while the sheet raises a SwiftUI `.alert`.
    enum TrackResult: Equatable {
        case started
        case promotedExisting
        case failed
    }

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    // MARK: - Deletion

    /// Reports the remove-bookmark analytics event. The caller still performs
    /// the delete on its own view model.
    func reportDeletion(of bookmark: Bookmark) {
        guard let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign else { return }

        application.analytics?.reportEvent(
            pageURL: "app://localhost/bookmarks",
            label: AnalyticsLabels.removeBookmark,
            value: AnalyticsLabels.addRemoveBookmarkValue(
                routeID: routeID,
                headsign: headsign,
                stopID: bookmark.stopID))
    }

    // MARK: - Bookmark Editor

    /// Builds the bookmark editor inside a navigation controller. Presentation
    /// is the caller's job.
    func makeBookmarkEditor(for bookmark: Bookmark, delegate: BookmarkEditorDelegate) -> UINavigationController {
        let editor = EditBookmarkViewController(
            application: application,
            stop: bookmark.stop,
            bookmark: bookmark,
            delegate: delegate
        )
        return UINavigationController(rootViewController: editor)
    }

    // MARK: - Live Activities

    /// The route name/headsign pair stored in a Live Activity's `StaticData`.
    /// Creation and reconciliation must apply the same fallbacks — comparing
    /// raw optionals against these stored values would never match a bookmark
    /// whose route name or headsign is missing.
    static func liveActivityKeys(for bookmark: Bookmark) -> (routeShortName: String, routeHeadsign: String) {
        // Use structured properties directly from the Bookmark model instead of parsing
        // the display name, which would break on hyphenated route names like "A-Line".
        (bookmark.routeShortName ?? bookmark.name, bookmark.tripHeadsign ?? "")
    }

    static func buildContentState(from arrivalDepartures: [ArrivalDeparture]) -> TripAttributes.ContentState? {
        guard !arrivalDepartures.isEmpty else {
            return nil
        }
        let arrivals = arrivalDepartures.prefix(3).map { arrDep in
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(arrDep.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: Array(arrivals))
    }

    /// Builds content for the trip the rider actually tracked: same stop, route,
    /// and destination as `departure`. Route-only matching mixes both directions
    /// at a transit center and shows the opposite bus's countdown (#1326).
    static func buildContentState(
        from arrivalDepartures: [ArrivalDeparture],
        matching departure: ArrivalDeparture
    ) -> TripAttributes.ContentState {
        let key = TripBookmarkKey(arrivalDeparture: departure)
        let sameTrip = arrivalDepartures
            .filter { TripBookmarkKey(arrivalDeparture: $0) == key }
            .sorted { $0.arrivalDepartureDate < $1.arrivalDepartureDate }
        let source = sameTrip.isEmpty ? [departure] : sameTrip
        return buildContentState(from: source)!
    }

    @discardableResult
    func startLiveActivity(for bookmark: Bookmark, arrivalDepartures: [ArrivalDeparture]) -> TrackResult {
        let (routeShortName, routeHeadsign) = Self.liveActivityKeys(for: bookmark)

        let routeColorHex = arrivalDepartures.first?.route.color?.toHex()
        let staticData = TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: bookmark.stopID,
            routeColorHex: routeColorHex,
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        // Tapping Track again on a bookmark that is already tracked — or tracking
        // the same trip from the stop page — would otherwise mint a second
        // activity for one stop, leaving the user with duplicate Lock Screen
        // cards and duplicate OBACloud push registrations. Re-Track still needs
        // to promote the existing activity: after A→B the Island is on B with A
        // demoted to 0, so tapping Track on A again must bump A (not just toast).
        if let existing = Activity<TripAttributes>.running(matching: staticData) {
            Logger.info("Live Activity already running for stop \(staticData.stopID) route \(staticData.routeShortName); promoting instead of duplicating.")
            let existingID = existing.id
            Task {
                await Activity<TripAttributes>.promoteToDynamicIsland(activityID: existingID)
            }
            showLiveActivityStartedToast()
            return .promotedExisting
        }

        guard let contentState = Self.buildContentState(from: arrivalDepartures) else {
            // Shouldn't happen — the context menu only offers Track once arrival
            // data has loaded — but if data was cleared between the menu render
            // and the tap, tell the user rather than silently doing nothing.
            Logger.error("Failed to build content state for Live Activity")
            return .failed
        }

        let attributes = TripAttributes(staticData: staticData)
        // Prominence so the Dynamic Island switches to this Track when another
        // trip is already live (#1189 Problem 2). Default score is 0 and equal
        // scores keep the first-started activity.
        let prominence = TripLiveActivityRelevance.prominenceScore()
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: TripLiveActivityRelevance.content(
                    state: contentState,
                    staleDate: nil,
                    relevanceScore: prominence
                ),
                pushType: .token
            )
            trackLiveActivity(activity, arrivalDepartures: arrivalDepartures)
            let activityID = activity.id
            Task {
                await Activity<TripAttributes>.demoteLivePeers(
                    exceptActivityID: activityID,
                    relativeTo: prominence
                )
            }
            Logger.info("Started Live Activity with ID: \(activity.id)")
            showLiveActivityStartedToast()
            return .started
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            return .failed
        }
    }

    /// Shared by the start path and the already-tracking guard, so a duplicate
    /// tap gets the same confirmation the first tap did rather than silently
    /// appearing to do nothing.
    private func showLiveActivityStartedToast() {
        let message = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen")
        ProgressHUD.showSuccessAndDismiss(message: message)
    }

    /// Hands `activity` to the app-scoped tracker, which owns the push-token and lifecycle
    /// observers. They deliberately outlive this controller — and every other screen — so that an
    /// activity is unregistered when it actually ends rather than when a view controller happens
    /// to be deallocated. See `LiveActivityTracker`.
    private func trackLiveActivity(_ activity: Activity<TripAttributes>, arrivalDepartures: [ArrivalDeparture]) {
        application.liveActivityTracker.track(
            activity: activity,
            metadata: .init(arrivalDepartures.first)
        )
    }
}
