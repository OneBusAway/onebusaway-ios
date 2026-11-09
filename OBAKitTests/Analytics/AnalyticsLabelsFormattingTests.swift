//
//  AnalyticsLabelsFormattingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `AnalyticsLabels` formatters and constant consistency.
///
/// Validates parameter combination formatting for bookmark toggles, nil headsign handling,
/// whitespace resilience, and contract stability of analytics event identifiers.
@Suite(.serialized)
struct AnalyticsLabelsFormattingTests {

    // MARK: - addRemoveBookmarkValue Formatting

    @Test func `addRemoveBookmarkValue formats standard route, headsign, and stopID`() {
        let formatted = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: "1_44",
            headsign: "Ballard",
            stopID: "1_10020"
        )
        #expect(formatted == "1_44_Ballard for 1_10020")
    }

    @Test func `addRemoveBookmarkValue handles nil headsign by using empty string`() {
        let formatted = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: "1_44",
            headsign: nil,
            stopID: "1_10020"
        )
        #expect(formatted == "1_44_ for 1_10020")
    }

    @Test func `addRemoveBookmarkValue handles empty headsign string identically to nil`() {
        let formatted = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: "1_44",
            headsign: "",
            stopID: "1_10020"
        )
        #expect(formatted == "1_44_ for 1_10020")
    }

    @Test func `addRemoveBookmarkValue handles headsign with special characters and slashes`() {
        let formatted = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: "40_550",
            headsign: "Bellevue / Via I-90 Express",
            stopID: "40_9901"
        )
        #expect(formatted == "40_550_Bellevue / Via I-90 Express for 40_9901")
    }

    @Test func `addRemoveBookmarkValue handles stopID with underscores and prefixes`() {
        let formatted = AnalyticsLabels.addRemoveBookmarkValue(
            routeID: "community_transit_115",
            headsign: "Aurora Village",
            stopID: "29_stop_54321"
        )
        #expect(formatted == "community_transit_115_Aurora Village for 29_stop_54321")
    }

    // MARK: - Core Event Constants Invariance

    @Test func `AnalyticsLabels core event strings match telemetry specifications`() {
        #expect(AnalyticsLabels.reportProblem == "report_problem")
        #expect(AnalyticsLabels.setRegionAutomatically == "Set region automatically")
        #expect(AnalyticsLabels.setRegionManually == "Set region manually")
        #expect(AnalyticsLabels.manuallySelectedRegionChanged == "selected manually")
        #expect(AnalyticsLabels.farePayment == "fare_payment")
        #expect(AnalyticsLabels.addBookmark == "Starred route")
        #expect(AnalyticsLabels.removeBookmark == "Unstarred route")
        #expect(AnalyticsLabels.searchSelected == "Search box selected")
    }

    @Test func `AnalyticsLabels map interaction constants match telemetry specifications`() {
        #expect(AnalyticsLabels.mapStopAnnotationTapped == "Clicked MapStopIcon")
        #expect(AnalyticsLabels.mapShowUserLocationButtonTapped == "Clicked My Location Button")
        #expect(AnalyticsLabels.mapLayerToggled == "Map Layer Toggled")
    }

    @Test func `AnalyticsLabels rental telemetry constants match telemetry specifications`() {
        #expect(AnalyticsLabels.rentalVehicleSelected == "Rental Vehicle Selected")
        #expect(AnalyticsLabels.rentalPlanTripTapped == "Rental Plan Trip Tapped")
        #expect(AnalyticsLabels.rentalDeepLinkTapped == "Rental Deep Link Tapped")
        #expect(AnalyticsLabels.rentalDeepLinkFallbackFired == "Rental Deep Link Fallback Fired")
        #expect(AnalyticsLabels.rentalRangeFilterChanged == "Rental Range Filter Changed")
    }

    @Test func `AnalyticsLabels donation telemetry constants match telemetry specifications`() {
        #expect(AnalyticsLabels.donationLearnMoreShown == "Donation Learn More Shown")
        #expect(AnalyticsLabels.donateButtonTapped == "Donation Button Tapped")
        #expect(AnalyticsLabels.donationSuccess == "Donation Success")
        #expect(AnalyticsLabels.donationError == "Donation Error")
        #expect(AnalyticsLabels.donationCanceled == "Donation Canceled")
        #expect(AnalyticsLabels.donationPushNotificationTapped == "Donation Push Notification Tapped")
        #expect(AnalyticsLabels.donationPushNotificationSuccess == "Donation Push Notification Success")
    }

    @Test func `AnalyticsLabels feedback telemetry constants match telemetry specifications`() {
        #expect(AnalyticsLabels.feedbackPromptShown == "Feedback Prompt Shown")
        #expect(AnalyticsLabels.feedbackPositive == "Feedback Positive")
        #expect(AnalyticsLabels.feedbackNegative == "Feedback Negative")
        #expect(AnalyticsLabels.feedbackDeferred == "Feedback Deferred")
        #expect(AnalyticsLabels.feedbackEmailOpened == "Feedback Email Opened")
        #expect(AnalyticsLabels.feedbackEmailSent == "Feedback Email Sent")
        #expect(AnalyticsLabels.feedbackEmailUnavailable == "Feedback Email Unavailable")
        #expect(AnalyticsLabels.feedbackEmailFailed == "Feedback Email Failed")
        #expect(AnalyticsLabels.rateAppRowTapped == "Rate App Row Tapped")
    }

    @Test func `AnalyticsKeys user defaults keys match expected namespace`() {
        #expect(AnalyticsKeys.reportingEnabledUserDefaultsKey == "reportingEnabledUserDefaultsKey")
    }
}
