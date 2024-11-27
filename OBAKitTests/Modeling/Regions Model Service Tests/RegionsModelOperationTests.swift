//
//  RegionsModelOperationTests.swift
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

// swiftlint:disable function_body_length force_cast

class RegionsModelOperationTests: OBATestCase {
    func testSuccessfulRequest() async throws {
        let dataLoader = regionsAPIService.dataLoader as! MockDataLoader
        stubRegions(dataLoader: dataLoader)

        let response = try await regionsAPIService.getRegions(apiPath: regionsAPIPath)

        let regions = response.list
        expect(regions.count) == 17

        let tampa = try XCTUnwrap(regions.first)

        expect(tampa.regionIdentifier) == 0
        expect(tampa.name) == "Tampa Bay"
        expect(tampa.versionInfo) == "2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf"
        expect(tampa.language) == "en_US"

        expect(tampa.supportsEmbeddedSocial).to(beFalse())
        expect(tampa.supportsOBADiscoveryAPIs).to(beTrue())
        expect(tampa.supportsOTPBikeshare).to(beTrue())
        expect(tampa.supportsSiriRealtimeAPIs).to(beTrue())
        expect(tampa.isActive).to(beTrue())
        expect(tampa.isExperimental).to(beFalse())

        expect(tampa.facebookURL).to(beNil())
        expect(tampa.contactEmail) == "onebusaway@gohart.org"
        expect(tampa.openTripPlannerContactEmail) == "otp-tampa@onebusaway.org"
        expect(tampa.twitterURL) == URL(string: "https://mobile.twitter.com/OBA_tampa")!

        expect(tampa.OBABaseURL) == URL(string: "https://api.tampa.onebusaway.org/api/")!
        expect(tampa.sidecarBaseURL) == URL(string: "https://onebusaway.co")!
        expect(tampa.siriBaseURL) == URL(string: "https://tampa.onebusaway.org/onebusaway-api-webapp/siri/")!
        expect(tampa.openTripPlannerURL) == URL(string: "https://otp.prod.obahart.org/otp/")!
        expect(tampa.stopInfoURL).to(beNil())

        expect(tampa.paymentWarningBody).to(beNil())
        expect(tampa.paymentWarningTitle).to(beNil())
        expect(tampa.paymentAndroidAppID) == "co.bytemark.flamingo"
        expect(tampa.paymentiOSAppStoreIdentifier) == "1487465395"
        expect(tampa.paymentiOSAppURLScheme) == "fb313213768708402HART"

        let open311 = try XCTUnwrap(tampa.open311Servers?.first)
        expect(open311.jurisdictionID).to(beNil())
        expect(open311.apiKey) == "937033cad3054ec58a1a8156dcdd6ad8a416af2f"
        expect(open311.baseURL) == URL(string: "https://seeclickfix.com/open311/v2/")!

        let serviceRect = tampa.serviceRect
        expect(serviceRect.minX).to(beCloseTo(72439895.2211))
        expect(serviceRect.minY).to(beCloseTo(112245249.3519))
        expect(serviceRect.maxX).to(beCloseTo(72956527.5911))
        expect(serviceRect.maxY).to(beCloseTo(112722187.8406))

        let pugetSound = regions[1]

        expect(pugetSound.name) == "Puget Sound"

        let mapRect = MKMapRect(x: 42206703.270115554, y: 92590980.991902918, width: 1338771.0533083975, height: 1897888.1099742353)
        expect(pugetSound.serviceRect.minX).to(beCloseTo(mapRect.minX))
        expect(pugetSound.serviceRect.minY).to(beCloseTo(mapRect.minY))
        expect(pugetSound.serviceRect.maxX).to(beCloseTo(mapRect.maxX))
        expect(pugetSound.serviceRect.maxY).to(beCloseTo(mapRect.maxY))

        expect(pugetSound.centerCoordinate.latitude).to(beCloseTo(47.795091214055))
        expect(pugetSound.centerCoordinate.longitude).to(beCloseTo(-122.49868405298474))
    }
}
