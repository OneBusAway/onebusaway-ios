//
//  ProximityMonitoringExtendedTests.swift
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

/// Extended edge-case tests for `ProximityMonitoringResult` and `RegionMonitoringFailureKind`.
///
/// Focuses on clamped radius comparisons, non-standard CLError codes,
/// NSError bridging, and Sendable equality invariants.
@Suite(.serialized)
struct ProximityMonitoringExtendedTests {

    // MARK: - Insufficient Authorization Invariants

    @Test func `Insufficient authorization correctly reflects all unpermitted states`() {
        let notDetermined = ProximityMonitoringResult.insufficientAuthorization(.notDetermined)
        let restricted = ProximityMonitoringResult.insufficientAuthorization(.restricted)
        let denied = ProximityMonitoringResult.insufficientAuthorization(.denied)
        let whenInUse = ProximityMonitoringResult.insufficientAuthorization(.authorizedWhenInUse)

        #expect(!notDetermined.isMonitoring)
        #expect(!restricted.isMonitoring)
        #expect(!denied.isMonitoring)
        #expect(!whenInUse.isMonitoring)

        #expect(notDetermined != restricted)
        #expect(denied != whenInUse)
    }

    // MARK: - RegionMonitoringFailureKind Error Bridging

    @Test func `RegionMonitoringFailureKind maps custom NSError domain to unknown`() {
        let customError = NSError(domain: "com.onebusaway.tests.custom", code: CLError.Code.denied.rawValue, userInfo: nil)
        let kind = RegionMonitoringFailureKind(error: customError)

        #expect(kind == .unknown)
        #expect(!kind.isTransient)
        #expect(kind.description == "unknown")
    }

    @Test func `RegionMonitoringFailureKind handles all transient delay codes`() {
        let setupDelayed = RegionMonitoringFailureKind(error: CLError(.regionMonitoringSetupDelayed))
        let responseDelayed = RegionMonitoringFailureKind(error: CLError(.regionMonitoringResponseDelayed))
        let network = RegionMonitoringFailureKind(error: CLError(.network))

        #expect(setupDelayed == .transient)
        #expect(setupDelayed.isTransient)
        #expect(setupDelayed.description == "transient")

        #expect(responseDelayed == .transient)
        #expect(responseDelayed.isTransient)

        #expect(network == .transient)
        #expect(network.isTransient)
    }

    @Test func `RegionMonitoringFailureKind handles permanent denial and rejection`() {
        let denied = RegionMonitoringFailureKind(error: CLError(.denied))
        let regionDenied = RegionMonitoringFailureKind(error: CLError(.regionMonitoringDenied))
        let failure = RegionMonitoringFailureKind(error: CLError(.regionMonitoringFailure))

        #expect(denied == .authorizationDenied)
        #expect(!denied.isTransient)
        #expect(denied.description == "authorizationDenied")

        #expect(regionDenied == .authorizationDenied)
        #expect(!regionDenied.isTransient)

        #expect(failure == .regionRejected)
        #expect(!failure.isTransient)
        #expect(failure.description == "regionRejected")
    }
}
