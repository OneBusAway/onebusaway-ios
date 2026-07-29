//
//  RegionsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length force_cast

@Suite(.serialized)
final class RegionsModelOperationTests: OBATestCase {
    @Test func `Successful request`() async throws {
        let dataLoader = regionsAPIService.dataLoader as! MockDataLoader
        stubRegions(dataLoader: dataLoader)

        let response = try await regionsAPIService.getRegions(apiPath: regionsAPIPath)

        let regions = response.list
        #expect(regions.count == 17)

        let tampa = try #require(regions.first)

        #expect(tampa.regionIdentifier == 0)
        #expect(tampa.name == "Tampa Bay")
        #expect(tampa.versionInfo == "2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf")
        #expect(tampa.language == "en_US")

        #expect(!tampa.supportsEmbeddedSocial)
        #expect(tampa.supportsOBADiscoveryAPIs)
        #expect(tampa.supportsOTPBikeshare)
        #expect(tampa.supportsSiriRealtimeAPIs)
        #expect(tampa.isActive)
        #expect(!tampa.isExperimental)

        #expect(tampa.facebookURL == nil)
        #expect(tampa.contactEmail == "onebusaway@gohart.org")
        #expect(tampa.openTripPlannerContactEmail == "otp-tampa@onebusaway.org")
        #expect(tampa.twitterURL == URL(string: "https://mobile.twitter.com/OBA_tampa")!)

        #expect(tampa.OBABaseURL == URL(string: "https://api.tampa.onebusaway.org/api/")!)
        #expect(tampa.sidecarBaseURL == URL(string: "https://onebusaway.co")!)
        #expect(tampa.siriBaseURL == URL(string: "https://tampa.onebusaway.org/onebusaway-api-webapp/siri/")!)
        #expect(tampa.openTripPlannerURL == URL(string: "https://otp.prod.obahart.org/otp/")!)
        #expect(tampa.stopInfoURL == nil)

        #expect(tampa.paymentWarningBody == nil)
        #expect(tampa.paymentWarningTitle == nil)
        #expect(tampa.paymentAndroidAppID == "co.bytemark.flamingo")
        #expect(tampa.paymentiOSAppStoreIdentifier == "1487465395")
        #expect(tampa.paymentiOSAppURLScheme == "fb313213768708402HART")

        let open311 = try #require(tampa.open311Servers?.first)
        #expect(open311.jurisdictionID == nil)
        #expect(open311.apiKey == "937033cad3054ec58a1a8156dcdd6ad8a416af2f")
        #expect(open311.baseURL == URL(string: "https://seeclickfix.com/open311/v2/")!)

        let serviceRect = tampa.serviceRect
        expectClose(serviceRect.minX, 72439895.2211)
        expectClose(serviceRect.minY, 112245249.3519)
        expectClose(serviceRect.maxX, 72956527.5911)
        expectClose(serviceRect.maxY, 112722187.8406)

        let pugetSound = regions[1]

        #expect(pugetSound.name == "Puget Sound")

        let mapRect = MKMapRect(x: 42206703.270115554, y: 92590980.991902918, width: 1338771.0533083975, height: 1897888.1099742353)
        expectClose(pugetSound.serviceRect.minX, mapRect.minX)
        expectClose(pugetSound.serviceRect.minY, mapRect.minY)
        expectClose(pugetSound.serviceRect.maxX, mapRect.maxX)
        expectClose(pugetSound.serviceRect.maxY, mapRect.maxY)

        expectClose(pugetSound.centerCoordinate.latitude, 47.795091214055)
        expectClose(pugetSound.centerCoordinate.longitude, -122.49868405298474)
    }

// WIP Fix for #777
//    func testDecoderError() async throws {
//        let dataLoader = regionsAPIService.dataLoader as! MockDataLoader
//        stubRegions(dataLoader: dataLoader, fixtureFile: "decoder-failure__regions-v3.json")
//
//        let response = try await regionsAPIService.getRegions(apiPath: regionsAPIPath)
//
//        let regions = response.list
//        #expect(regions.count == 17)
//    }
}
