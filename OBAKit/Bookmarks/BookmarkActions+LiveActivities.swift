//
//  BookmarkActions+LiveActivities.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import OBAKitCore

extension BookmarkActions {
    /// Pushes fresh arrivals into the running bookmark Live Activities, and re-arms
    /// push-token and lifecycle tracking for ones still running after a relaunch.
    ///
    /// Called by whichever surface just loaded bookmark arrivals: the Bookmarks
    /// tab, or the map panel's home sheet, which has no tab.
    ///
    /// - Parameter arrivalDepartures: A bookmark's loaded arrivals, or nil when
    ///   that bookmark's haven't been loaded. Nil leaves its activity's content
    ///   alone rather than showing it no departures.
    static func updateRunningLiveActivities(
        application: Application,
        arrivalDepartures: (Bookmark) -> [ArrivalDeparture]?
    ) {
        let activities = Activity<TripAttributes>.activities
        for activity in activities {
            let staticData = activity.attributes.staticData
            let matchingBookmark = application.userDataStore.bookmarks.first(where: { bookmark in
                // Bookmark identity is unpinned (`tripID: ""`). Empty tripID is a
                // wildcard in `tracksSameTrip`, so this still reconciles with a
                // stop-page activity that carries a concrete trip — same rule the
                // start paths' duplicate guards use.
                let keys = BookmarkActions.liveActivityKeys(for: bookmark)
                let bookmarkIdentity = TripAttributes.StaticData(
                    routeShortName: keys.routeShortName,
                    routeHeadsign: keys.routeHeadsign,
                    stopID: bookmark.stopID,
                    tripID: ""
                )
                return bookmarkIdentity.tracksSameTrip(as: staticData)
            })
            let loadedArrivals = matchingBookmark.flatMap(arrivalDepartures)
            let arrivals = loadedArrivals ?? []
            let primaryArrival = BookmarkActions.refreshPrimaryArrival(
                for: staticData,
                arrivalDepartures: arrivals
            )

            let contentState: TripAttributes.ContentState? = {
                guard matchingBookmark != nil, loadedArrivals != nil else { return nil }
                return BookmarkActions.buildRefreshContentState(
                    for: staticData,
                    arrivalDepartures: arrivals
                )
            }()

            if matchingBookmark != nil, loadedArrivals != nil, let contentState {
                // Re-arm the push token/lifecycle observers on relaunch. `startLiveActivity`
                // only tracks activities it creates in-session, so without this a Live Activity
                // that's still running after a relaunch would never re-establish its observers
                // and would never unregister when it later ends. Guarded so repeated calls to
                // updateRunningLiveActivities() don't cancel/rebuild an already-armed task — and
                // because the tracker is app-scoped, the guard also covers an activity started
                // from the stop page, which we must not steal the observers out from under.
                //
                // Deliberately keyed on the token task and not on `isTracking`: an activity that
                // the sweep below could only lifecycle-observe (no matching bookmark at the time)
                // must still be upgradable to a full registration once its bookmark reappears.
                //
                // Metadata must be the pinned arrival when `staticData.tripID` is set —
                // `arrivalDepartures.first` is soonest-first and would re-POST the wrong
                // vehicle to OBACloud after relaunch (#1334).
                if !application.liveActivityTracker.isForwardingPushToken(activityID: activity.id) {
                    application.liveActivityTracker.track(
                        activity: activity,
                        metadata: .init(primaryArrival)
                    )
                }
                // Coalesce per activity ID. The worker re-fetches the activity
                // before applying content, so its current relevance score is
                // preserved across the asynchronous hop (#1197).
                let activityID = activity.id
                Task {
                    await LiveActivityUpdateCoalescer.shared.schedule(
                        activityID: activityID,
                        state: contentState
                    )
                }
            } else if !application.liveActivityTracker.isTracking(activityID: activity.id) {
                // No bookmark/arrival data to register push updates with, but the activity is
                // still running (and may have a delete URL persisted from a prior session).
                // Arm just the lifecycle observer so dismiss/end still triggers `unregister`.
                application.liveActivityTracker.observeLifecycle(of: activity)
            }
        }
    }
}
