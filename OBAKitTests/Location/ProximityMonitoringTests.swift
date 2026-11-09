//
//  ProximityMonitoringTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `ProximityMonitoringResult` and `RegionMonitoringFailureKind`.
///
/// Validates monitoring state classification, radius clamping indicators,
/// transient vs. permanent failure discrimination, and human-readable descriptions.
@Suite(.serialized)
struct ProximityMonitoringTests {

    // MARK: - ProximityMonitoringResult isMonitoring

    @Test func `ProximityMonitoringResult isMonitoring returns true for started cases`() {
        let standardStart = ProximityMonitoringResult.started
        #expect(standardStart.isMonitoring)

        let clampedStart = ProximityMonitoringResult.startedWithClampedRadius(
            requested: 400.0,
            monitored: 250.0
        )
        #expect(clampedStart.isMonitoring)
    }

    @Test func `ProximityMonitoringResult isMonitoring returns false for unstarted cases`() {
        let authDenied = ProximityMonitoringResult.insufficientAuthorization(.denied)
        #expect(!authDenied.isMonitoring)

        let authWhenInUse = ProximityMonitoringResult.insufficientAuthorization(.authorizedWhenInUse)
        #expect(!authWhenInUse.isMonitoring)

        let limitReached = ProximityMonitoringResult.regionLimitReached(limit: 20)
        #expect(!limitReached.isMonitoring)
    }

    @Test func `ProximityMonitoringResult equality`() {
        #expect(ProximityMonitoringResult.started == ProximityMonitoringResult.started)
        #expect(
            ProximityMonitoringResult.startedWithClampedRadius(requested: 500, monitored: 300) ==
            ProximityMonitoringResult.startedWithClampedRadius(requested: 500, monitored: 300)
        )
        #expect(
            ProximityMonitoringResult.startedWithClampedRadius(requested: 500, monitored: 300) !=
            ProximityMonitoringResult.startedWithClampedRadius(requested: 500, monitored: 250)
        )
        #expect(
            ProximityMonitoringResult.insufficientAuthorization(.denied) ==
            ProximityMonitoringResult.insufficientAuthorization(.denied)
        )
        #expect(
            ProximityMonitoringResult.insufficientAuthorization(.denied) !=
            ProximityMonitoringResult.insufficientAuthorization(.restricted)
        )
        #expect(
            ProximityMonitoringResult.regionLimitReached(limit: 20) ==
            ProximityMonitoringResult.regionLimitReached(limit: 20)
        )
        #expect(
            ProximityMonitoringResult.regionLimitReached(limit: 20) !=
            ProximityMonitoringResult.regionLimitReached(limit: 15)
        )
        #expect(
            ProximityMonitoringResult.started !=
            ProximityMonitoringResult.regionLimitReached(limit: 20)
        )
    }

    // MARK: - RegionMonitoringFailureKind Classification

    @Test func `RegionMonitoringFailureKind classifies non-CLError as unknown`() {
        let generalError = NSError(domain: "org.opentransit.tests", code: 999, userInfo: nil)
        let kind = RegionMonitoringFailureKind(error: generalError)
        #expect(kind == .unknown)
        #expect(!kind.isTransient)
    }

    @Test func `RegionMonitoringFailureKind classifies CLError denied as authorizationDenied`() {
        let denied = RegionMonitoringFailureKind(error: CLError(.denied))
        #expect(denied == .authorizationDenied)
        #expect(!denied.isTransient)

        let regionDenied = RegionMonitoringFailureKind(error: CLError(.regionMonitoringDenied))
        #expect(regionDenied == .authorizationDenied)
        #expect(!regionDenied.isTransient)
    }

    @Test func `RegionMonitoringFailureKind classifies CLError regionMonitoringFailure as regionRejected`() {
        let rejected = RegionMonitoringFailureKind(error: CLError(.regionMonitoringFailure))
        #expect(rejected == .regionRejected)
        #expect(!rejected.isTransient)
    }

    @Test func `RegionMonitoringFailureKind classifies transient CLError codes`() {
        let setupDelayed = RegionMonitoringFailureKind(error: CLError(.regionMonitoringSetupDelayed))
        #expect(setupDelayed == .transient)
        #expect(setupDelayed.isTransient)

        let responseDelayed = RegionMonitoringFailureKind(error: CLError(.regionMonitoringResponseDelayed))
        #expect(responseDelayed == .transient)
        #expect(responseDelayed.isTransient)

        let network = RegionMonitoringFailureKind(error: CLError(.network))
        #expect(network == .transient)
        #expect(network.isTransient)
    }

    @Test func `RegionMonitoringFailureKind classifies unrelated CLError codes as unknown`() {
        let headingFailure = RegionMonitoringFailureKind(error: CLError(.headingFailure))
        #expect(headingFailure == .unknown)
        #expect(!headingFailure.isTransient)

        let locationUnknown = RegionMonitoringFailureKind(error: CLError(.locationUnknown))
        #expect(locationUnknown == .unknown)
        #expect(!locationUnknown.isTransient)

        let promptDeclined = RegionMonitoringFailureKind(error: CLError(.promptDeclined))
        #expect(promptDeclined == .unknown)
        #expect(!promptDeclined.isTransient)
    }

    // MARK: - CustomStringConvertible Description

    @Test func `RegionMonitoringFailureKind description matches expected string tokens`() {
        #expect(RegionMonitoringFailureKind.authorizationDenied.description == "authorizationDenied")
        #expect(RegionMonitoringFailureKind.regionRejected.description == "regionRejected")
        #expect(RegionMonitoringFailureKind.transient.description == "transient")
        #expect(RegionMonitoringFailureKind.unknown.description == "unknown")
    }

    // MARK: - Raw Values and ObjC Representation

    @Test func `RegionMonitoringFailureKind raw values are stable`() {
        #expect(RegionMonitoringFailureKind.authorizationDenied.rawValue == 0)
        #expect(RegionMonitoringFailureKind.regionRejected.rawValue == 1)
        #expect(RegionMonitoringFailureKind.transient.rawValue == 2)
        #expect(RegionMonitoringFailureKind.unknown.rawValue == 3)
    }
}
