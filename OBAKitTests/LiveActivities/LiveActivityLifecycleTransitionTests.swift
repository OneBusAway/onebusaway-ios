//
//  LiveActivityLifecycleTransitionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKitCore

/// Comprehensive test suite locking down the Live Activity lifecycle states:
/// Active (fresh), Stale, Delayed, Ended (departed), and Dismissed / Inactive,
/// including visual chrome, accessibility labels, exact timestamps, and
/// Dynamic Island relevance score transitions.
@MainActor
@Suite(.serialized)
final class LiveActivityLifecycleTransitionTests {

    private static let formatters = Formatters(
        locale: Locale(identifier: "en_US"),
        calendar: Calendar(identifier: .gregorian),
        themeColors: ThemeColors.shared
    )
    private let formatters = LiveActivityLifecycleTransitionTests.formatters
    private let presenter = TripActivityPresenter(formatters: LiveActivityLifecycleTransitionTests.formatters)

    private let staticData = TripAttributes.StaticData(
        routeShortName: "49",
        routeHeadsign: "Downtown Seattle",
        stopID: "1_75403",
        regionID: 1,
        tripID: "trip_49"
    )

    /// Base reference epoch: 2023-11-14 22:13:20 UTC.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeArrival(
        offsetSeconds: Int,
        status: TripAttributes.ContentState.ScheduleStatusValue = .onTime,
        deviation: Int = 0,
        isArrival: Bool = false,
        referenceDate: Date? = nil
    ) -> TripAttributes.ContentState.ArrivalInfo {
        let base = referenceDate ?? now
        return TripAttributes.ContentState.ArrivalInfo(
            departureTime: Int(base.timeIntervalSince1970) + offsetSeconds,
            scheduleStatus: status,
            scheduleDeviation: deviation,
            isArrival: isArrival
        )
    }

    // MARK: - 1. Active State (Fresh)

    @Test func `Active state renders fully opaque chrome`() {
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: false) == 1.0)
    }

    @Test func `Active state accessibility segments omit stale warning`() {
        let arrival = makeArrival(offsetSeconds: 300, status: .onTime, deviation: 0, isArrival: true)
        let state = TripAttributes.ContentState(arrivals: [arrival])

        let segments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state,
            isStale: false,
            now: now
        )

        let spoken = TripActivityPresenter.spokenString(segments, now: now)
        #expect(!spoken.contains(LiveActivityStaleChrome.warningText))
        #expect(segments.last != .text(LiveActivityStaleChrome.warningText))
        #expect(spoken.contains("Route 49"))
        #expect(spoken.contains("Downtown Seattle"))
        #expect(spoken.contains("arrives on time"))
    }

    @Test func `Active state on-time arrival displays single time without strikethrough`() {
        let arrival = makeArrival(offsetSeconds: 600, status: .onTime, deviation: 0)
        let display = presenter.timeDisplay(for: arrival)

        #expect(display.scheduledTimeText == nil)
        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(600)))
        #expect(presenter.color(for: arrival) == formatters.colorForScheduleStatus(.onTime))
    }

    // MARK: - 2. Stale State

    @Test func `Stale state dims content chrome to fifty-five percent`() {
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: true) == 0.55)
    }

    @Test func `Stale warning text and color match design specifications`() {
        #expect(LiveActivityStaleChrome.warningText == "This data may be out of date.")
        #expect(LiveActivityStaleChrome.warningColor == Color(uiColor: ThemeColors.shared.warningText))
    }

    @Test func `Stale state appends warning at the end of accessibility segments`() {
        let arrival = makeArrival(offsetSeconds: 300, status: .onTime, deviation: 0)
        let state = TripAttributes.ContentState(arrivals: [arrival])

        let freshSegments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state,
            isStale: false,
            now: now
        )
        let staleSegments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state,
            isStale: true,
            now: now
        )

        // Fresh segments do not have warning
        #expect(freshSegments.last != .text(LiveActivityStaleChrome.warningText))

        // Stale segments contain exactly fresh segments plus the warning at the end
        #expect(staleSegments.count == freshSegments.count + 1)
        #expect(staleSegments.last == .text(LiveActivityStaleChrome.warningText))

        let spokenStale = TripActivityPresenter.spokenString(staleSegments, now: now)
        #expect(spokenStale.hasSuffix(LiveActivityStaleChrome.warningText))
    }

    @Test func `Transition from active to stale preserves arrival details while altering chrome`() {
        let arrival = makeArrival(offsetSeconds: 420, status: .onTime, deviation: 0, isArrival: true)
        let state = TripAttributes.ContentState(arrivals: [arrival])

        let activeOpacity = LiveActivityStaleChrome.contentOpacity(isStale: false)
        let staleOpacity = LiveActivityStaleChrome.contentOpacity(isStale: true)
        #expect(activeOpacity == 1.0)
        #expect(staleOpacity == 0.55)

        // The arrival presentation details (times, adherence, minute text) remain identical
        #expect(presenter.minuteText(for: arrival, now: now) == "7m")
        #expect(presenter.deviationLabel(for: arrival, now: now) == "arrives on time")
        #expect(presenter.timeDisplay(for: arrival).expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(420)))
        #expect(presenter.primaryColor(for: state, now: now) == formatters.colorForScheduleStatus(.onTime))
    }

    // MARK: - 3. Delayed State

    @Test func `Delayed arrival formats deviation label and late status color`() {
        // 180 seconds = 3 minutes late
        let arrivingTrip = makeArrival(offsetSeconds: 480, status: .delayed, deviation: 180, isArrival: true)
        #expect(presenter.deviationLabel(for: arrivingTrip, now: now) == "arrives 3 min late")
        #expect(presenter.deviationLabel(for: arrivingTrip, now: now).contains("3 min late"))
        #expect(presenter.color(for: arrivingTrip) == formatters.colorForScheduleStatus(.delayed))

        let departingTrip = makeArrival(offsetSeconds: 480, status: .delayed, deviation: 180, isArrival: false)
        #expect(presenter.deviationLabel(for: departingTrip, now: now) == "departs 3 min late")
        #expect(presenter.deviationLabel(for: departingTrip, now: now).contains("3 min late"))
        #expect(presenter.color(for: departingTrip) == formatters.colorForScheduleStatus(.delayed))
    }

    @Test func `Delayed arrival rounds raw second deviation to nearest minute`() {
        // 95 seconds = 1m35s, should round up to 2 min late
        let arrivalRoundUp = makeArrival(offsetSeconds: 480, status: .delayed, deviation: 95, isArrival: true)
        #expect(presenter.deviationLabel(for: arrivalRoundUp, now: now) == "arrives 2 min late")
        #expect(presenter.deviationLabel(for: arrivalRoundUp, now: now).contains("2 min late"))

        // 65 seconds = 1m05s, should round down to 1 min late
        let arrivalRoundDown = makeArrival(offsetSeconds: 480, status: .delayed, deviation: 65, isArrival: true)
        #expect(presenter.deviationLabel(for: arrivalRoundDown, now: now) == "arrives 1 min late")
        #expect(presenter.deviationLabel(for: arrivalRoundDown, now: now).contains("1 min late"))

        // Departing counterpart
        let departure = makeArrival(offsetSeconds: 480, status: .delayed, deviation: 95, isArrival: false)
        #expect(presenter.deviationLabel(for: departure, now: now) == "departs 2 min late")
        #expect(presenter.deviationLabel(for: departure, now: now).contains("2 min late"))
    }

    @Test func `Delayed arrival time display presents scheduled time struck-through alongside expected time`() {
        // Expected departure at now + 600s, deviation is 300s (5 min late)
        // Timetable scheduled time was at now + 300s
        let arrival = makeArrival(offsetSeconds: 600, status: .delayed, deviation: 300)
        let display = presenter.timeDisplay(for: arrival)

        #expect(display.scheduledTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(300)))
        #expect(display.expectedTimeText == formatters.timeFormatter.string(from: now.addingTimeInterval(600)))
        #expect(display.scheduledTimeText != nil)
        #expect(display.scheduledTimeText != display.expectedTimeText)
    }

    @Test func `Delayed arrival VoiceOver spoken text includes lateness and clock times`() {
        let arrival = makeArrival(offsetSeconds: 510, status: .delayed, deviation: 180)
        let state = TripAttributes.ContentState(arrivals: [arrival])

        let segments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state,
            isStale: false,
            now: now
        )
        let spoken = TripActivityPresenter.spokenString(segments, now: now)

        #expect(spoken.contains("3 min late"))
        #expect(spoken.contains(formatters.timeFormatter.string(from: now.addingTimeInterval(510))))
    }

    // MARK: - 4. Ended State (Departed)

    @Test func `Arrival in the past renders past temporal state`() {
        // 120 seconds in the past
        let departedArrival = makeArrival(offsetSeconds: -120, status: .onTime, deviation: 0)

        #expect(presenter.minuteText(for: departedArrival, now: now) == "-2m")
        #expect(presenter.deviationLabel(for: departedArrival, now: now) == "departed on time")

        // Past delayed departure
        let pastDelayed = makeArrival(offsetSeconds: -180, status: .delayed, deviation: 120)
        #expect(presenter.minuteText(for: pastDelayed, now: now) == "-3m")
        #expect(presenter.deviationLabel(for: pastDelayed, now: now) == "departed 2 min late")
    }

    @Test func `Arrival occurring at current minute renders NOW`() {
        let currentArrival = makeArrival(offsetSeconds: 0, status: .onTime, deviation: 0)
        #expect(presenter.minuteText(for: currentArrival, now: now) == "NOW")
    }

    @Test func `Primary color defaults to unknown status color when all arrivals have departed`() {
        let departedArrival = makeArrival(offsetSeconds: -60, status: .onTime, deviation: 0)
        let endedState = TripAttributes.ContentState(arrivals: [departedArrival])

        // upcomingArrivals filters out departures in the past
        #expect(endedState.upcomingArrivals(now: now).isEmpty)
        #expect(presenter.primaryColor(for: endedState, now: now) == formatters.colorForScheduleStatus(.unknown))

        // When upcoming arrivals remain, primary color is active status color
        let activeArrival = makeArrival(offsetSeconds: 300, status: .onTime, deviation: 0)
        let activeState = TripAttributes.ContentState(arrivals: [departedArrival, activeArrival])
        #expect(presenter.primaryColor(for: activeState, now: now) == formatters.colorForScheduleStatus(.onTime))
    }

    @Test func `Spoken segments for ended activity with no upcoming arrivals still identify route`() {
        let departedArrival = makeArrival(offsetSeconds: -120, status: .onTime, deviation: 0)
        let endedState = TripAttributes.ContentState(arrivals: [departedArrival])

        let segments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: endedState,
            isStale: false,
            now: now
        )
        let spoken = TripActivityPresenter.spokenString(segments, now: now)

        #expect(spoken == "Route 49, Downtown Seattle")
    }

    // MARK: - 5. Dismissed / Inactive States

    @Test func `LiveActivityRegistry treats active and stale as live, ended and dismissed as dead`() {
        #expect(LiveActivityRegistry.isLive(.active))
        #expect(LiveActivityRegistry.isLive(.stale))
        #expect(!LiveActivityRegistry.isLive(.ended))
        #expect(!LiveActivityRegistry.isLive(.dismissed))
    }

    // MARK: - 6. Relevance, Promotion, and Exact Dates

    @Test func `TripLiveActivityRelevance prominence score is strictly positive and monotonic`() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_100)

        let score1 = TripLiveActivityRelevance.prominenceScore(now: t1)
        let score2 = TripLiveActivityRelevance.prominenceScore(now: t2)

        #expect(score1 > TripLiveActivityRelevance.demotedScore)
        #expect(score2 > score1)
        #expect(score1 == 1_700_000_000)
        #expect(score2 == 1_700_000_100)
    }

    @Test func `Content preserving relevance maintains existing score across updates`() {
        let initialState = TripAttributes.ContentState(arrivals: [makeArrival(offsetSeconds: 300)])
        let initialContent = TripLiveActivityRelevance.content(
            state: initialState,
            staleDate: nil,
            relevanceScore: 1_700_000_050
        )

        let updatedArrival = makeArrival(offsetSeconds: 240, status: .delayed, deviation: 60)
        let updatedState = TripAttributes.ContentState(arrivals: [updatedArrival])
        let updatedStaleDate = Date(timeIntervalSince1970: 1_700_000_120)

        let preserved = TripLiveActivityRelevance.contentPreservingRelevance(
            state: updatedState,
            staleDate: updatedStaleDate,
            existing: initialContent
        )

        #expect(preserved.relevanceScore == initialContent.relevanceScore)
        #expect(preserved.relevanceScore == 1_700_000_050)
        #expect(preserved.state == updatedState)
        #expect(preserved.staleDate == updatedStaleDate)
    }

    @Test func `Promotion stale date preserves existing marker on score-only bump but resets on fresh arrivals`() {
        let existingStaleDate = Date(timeIntervalSince1970: 1_700_000_300)

        // Score-only bump (installing: nil)
        let scoreOnlyStaleDate = TripLiveActivityRelevance.promotionStaleDate(
            installing: nil,
            existing: existingStaleDate
        )
        #expect(scoreOnlyStaleDate == existingStaleDate)

        // Fresh arrivals (installing: non-nil)
        let freshState = TripAttributes.ContentState(arrivals: [makeArrival(offsetSeconds: 600)])
        let freshArrivalsStaleDate = TripLiveActivityRelevance.promotionStaleDate(
            installing: freshState,
            existing: existingStaleDate
        )
        #expect(freshArrivalsStaleDate == nil)
    }

    // MARK: - 7. End-to-End Multi-Step Lifecycle Progression

    @Test func `End-to-end active to delayed and stale transition`() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Step 1: User tracks trip at t0 (Active, fresh)
        let initialArrival = makeArrival(offsetSeconds: 600, status: .onTime, deviation: 0, referenceDate: t0)
        let state1 = TripAttributes.ContentState(arrivals: [initialArrival])
        let score1 = TripLiveActivityRelevance.prominenceScore(now: t0)
        let content1 = TripLiveActivityRelevance.content(state: state1, staleDate: nil, relevanceScore: score1)

        #expect(content1.relevanceScore == 1_700_000_000)
        #expect(content1.staleDate == nil)
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: false) == 1.0)
        #expect(LiveActivityRegistry.isLive(.active))

        // Step 2: Push update introduces a delay and arms stale date at t0 + 60s
        let delayedArrival = makeArrival(offsetSeconds: 660, status: .delayed, deviation: 120, isArrival: true, referenceDate: t0)
        let state2 = TripAttributes.ContentState(arrivals: [delayedArrival])
        let pushStaleDate = t0.addingTimeInterval(60)
        let content2 = TripLiveActivityRelevance.contentPreservingRelevance(
            state: state2,
            staleDate: pushStaleDate,
            existing: content1
        )

        #expect(content2.relevanceScore == score1) // score preserved
        #expect(content2.staleDate == pushStaleDate)
        #expect(presenter.deviationLabel(for: delayedArrival, now: t0) == "arrives 2 min late")
        #expect(presenter.deviationLabel(for: delayedArrival, now: t0).contains("2 min late"))
        #expect(presenter.color(for: delayedArrival) == formatters.colorForScheduleStatus(.delayed))

        // Step 3: Clock advances past pushStaleDate without new network updates (Stale)
        let tStale = t0.addingTimeInterval(75)
        #expect(tStale > pushStaleDate)
        #expect(LiveActivityRegistry.isLive(.stale))
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: true) == 0.55)

        let staleSegments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state2,
            isStale: true,
            now: tStale
        )
        #expect(staleSegments.last == .text(LiveActivityStaleChrome.warningText))
    }

    @Test func `End-to-end promotion, freshness recovery, departure, and dismissal`() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let delayedArrival = makeArrival(offsetSeconds: 660, status: .delayed, deviation: 120, referenceDate: t0)
        let state2 = TripAttributes.ContentState(arrivals: [delayedArrival])
        let pushStaleDate = t0.addingTimeInterval(60)
        let content2 = TripLiveActivityRelevance.content(
            state: state2,
            staleDate: pushStaleDate,
            relevanceScore: 1_700_000_000
        )

        // Step 4: User re-tracks without network response (score-only bump retains staleDate)
        let tReTrack = t0.addingTimeInterval(80)
        let reTrackStaleDate = TripLiveActivityRelevance.promotionStaleDate(
            installing: nil,
            existing: content2.staleDate
        )
        let scoreReTrack = TripLiveActivityRelevance.prominenceScore(now: tReTrack)
        let content4 = TripLiveActivityRelevance.content(
            state: content2.state,
            staleDate: reTrackStaleDate,
            relevanceScore: scoreReTrack
        )

        #expect(content4.relevanceScore > content2.relevanceScore)
        #expect(content4.staleDate == pushStaleDate) // preserves push-set stale date

        // Step 5: Fresh network response arrives (resets staleDate to nil, returns to active)
        let refreshedArrival = makeArrival(offsetSeconds: 500, status: .onTime, deviation: 0, referenceDate: tReTrack)
        let state5 = TripAttributes.ContentState(arrivals: [refreshedArrival])
        let freshStaleDate = TripLiveActivityRelevance.promotionStaleDate(
            installing: state5,
            existing: content4.staleDate
        )
        let content5 = TripLiveActivityRelevance.contentPreservingRelevance(
            state: state5,
            staleDate: freshStaleDate,
            existing: content4
        )

        #expect(content5.staleDate == nil)
        #expect(LiveActivityStaleChrome.contentOpacity(isStale: false) == 1.0)
        let freshSegments = presenter.accessibilitySegments(
            staticData: staticData,
            contentState: state5,
            isStale: false,
            now: tReTrack
        )
        #expect(freshSegments.last != .text(LiveActivityStaleChrome.warningText))

        // Step 6: Bus departs (Ended)
        let tDeparted = tReTrack.addingTimeInterval(600)
        #expect(state5.upcomingArrivals(now: tDeparted).isEmpty)
        #expect(presenter.primaryColor(for: state5, now: tDeparted) == formatters.colorForScheduleStatus(.unknown))
        #expect(presenter.minuteText(for: refreshedArrival, now: tDeparted).contains("-"))

        // Step 7: Activity lifecycle completes (Ended / Dismissed)
        #expect(!LiveActivityRegistry.isLive(.ended))
        #expect(!LiveActivityRegistry.isLive(.dismissed))
    }
}
