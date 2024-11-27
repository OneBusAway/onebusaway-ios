//
//  RegionsEncodingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable function_body_length force_try

class RegionsEncodingTests: OBATestCase {

    func testRoundtrippingRegion() {
        let regionsObjects = try! Fixtures.loadRESTAPIPayload(type: [Region].self, fileName: "regions-v3.json")

        expect(regionsObjects.count) == 17

        let tampa = regionsObjects[0]
        expect(tampa.name) == "Tampa Bay"
        expect(tampa.isCustom).to(beFalse())

        let plistData = try! PropertyListEncoder().encode(regionsObjects)
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plistData)
        let tampaRT = roundTripped[0]

        expect(roundTripped.count) == 17

        expect(tampaRT.regionIdentifier) == 0
        expect(tampaRT.name) == "Tampa Bay"

        expect(tampaRT.versionInfo) == "2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf"
        expect(tampaRT.language) == "en_US"

        expect(tampaRT.supportsEmbeddedSocial).to(beFalse())
        expect(tampaRT.supportsOBADiscoveryAPIs).to(beTrue())
        expect(tampaRT.supportsOTPBikeshare).to(beTrue())
        expect(tampaRT.supportsSiriRealtimeAPIs).to(beTrue())
        expect(tampaRT.isActive).to(beTrue())
        expect(tampaRT.isExperimental).to(beFalse())
        expect(tampaRT.isCustom).to(beFalse())

        expect(tampaRT.facebookURL).to(beNil())
        expect(tampaRT.contactEmail) == "onebusaway@gohart.org"
        expect(tampaRT.openTripPlannerContactEmail) == "otp-tampa@onebusaway.org"
        expect(tampaRT.twitterURL) == URL(string: "https://mobile.twitter.com/OBA_tampa")!

        expect(tampaRT.OBABaseURL) == URL(string: "https://api.tampa.onebusaway.org/api/")!
        expect(tampa.sidecarBaseURL) == URL(string: "https://onebusaway.co")!
        expect(tampaRT.siriBaseURL) == URL(string: "https://tampa.onebusaway.org/onebusaway-api-webapp/siri/")!
        expect(tampaRT.openTripPlannerURL) == URL(string: "https://otp.prod.obahart.org/otp/")!
        expect(tampaRT.stopInfoURL).to(beNil())

        expect(tampaRT.paymentWarningBody).to(beNil())
        expect(tampaRT.paymentWarningTitle).to(beNil())
        expect(tampaRT.paymentAndroidAppID) == "co.bytemark.flamingo"
        expect(tampaRT.paymentiOSAppStoreIdentifier) == "1487465395"
        expect(tampaRT.paymentiOSAppURLScheme) == "fb313213768708402HART"

        let open311 = tampaRT.open311Servers!.first!
        expect(open311.jurisdictionID).to(beNil())
        expect(open311.apiKey) == "937033cad3054ec58a1a8156dcdd6ad8a416af2f"
        expect(open311.baseURL) == URL(string: "https://seeclickfix.com/open311/v2/")!

        let bounds = tampaRT.regionBounds
        expect(bounds[0].lat).to(beCloseTo(27.976910500000002))
        expect(bounds[0].lon).to(beCloseTo(-82.445851))
        expect(bounds[0].latSpan).to(beCloseTo(0.5424609999999994))
        expect(bounds[0].lonSpan).to(beCloseTo(0.576357999999999))

        expect(bounds[1].lat).to(beCloseTo(27.919249999999998))
        expect(bounds[1].lon).to(beCloseTo(-82.652145))
        expect(bounds[1].latSpan).to(beCloseTo(0.47208000000000183))
        expect(bounds[1].lonSpan).to(beCloseTo(0.3967700000000036))
    }

    func testCustomRegions_creation() {
        let customRegion = Fixtures.customMinneapolisRegion

        expect(customRegion.name) == "Custom Region"
        expect(customRegion.OBABaseURL.absoluteString) == "http://www.example.com"
        expect(customRegion.contactEmail) == "contact@example.com"

        expect(customRegion.serviceRect.origin.coordinate.latitude).to(beCloseTo(44.9778, within: 0.1))
        expect(customRegion.serviceRect.origin.coordinate.longitude).to(beCloseTo(-93.2650, within: 0.1))
        expect(customRegion.serviceRect.height).to(beCloseTo(9485.2270, within: 0.1))
        expect(customRegion.serviceRect.width).to(beCloseTo(9453.3477, within: 0.1))
    }

    func testCustomRegions_roundtripping() {
        let customRegion = Fixtures.customMinneapolisRegion
        let plistData = try! PropertyListEncoder().encode([customRegion])
        let roundTripped = try! PropertyListDecoder().decode([Region].self, from: plistData)
        let customRegionRT = roundTripped[0]

        expect(customRegionRT.name) == "Custom Region"
        expect(customRegionRT.OBABaseURL.absoluteString) == "http://www.example.com"
        expect(customRegionRT.contactEmail) == "contact@example.com"

        expect(customRegionRT.serviceRect.origin.coordinate.latitude).to(beCloseTo(44.9778, within: 0.1))
        expect(customRegionRT.serviceRect.origin.coordinate.longitude).to(beCloseTo(-93.2650, within: 0.1))
        expect(customRegionRT.serviceRect.height).to(beCloseTo(9485.2270, within: 0.1))
        expect(customRegionRT.serviceRect.width).to(beCloseTo(9453.3477, within: 0.1))
    }
}
