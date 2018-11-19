//
//  RegionsModelOperationTests.swift
//  OBANetworkingKitTests
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
import CoreLocation
import MapKit
import OBATestHelpers
@testable import OBANetworkingKit

class RegionsModelOperationTests: OBATestCase {
    func testSuccessfulRequest() {
        stub(condition: isHost(self.regionsHost) && isPath(RegionsOperation.apiPath)) { _ in
            return self.JSONFile(named: "regions-v3.json")
        }

        waitUntil { (done) in
            let op = self.regionsModelService.getRegions()
            op.completionBlock = {
                let regions = op.regions
                expect(regions.count) == 12

                expect(op.responseData).toNot(beNil())

                let tampa = regions.first!

                expect(tampa.regionIdentifier) == 0
                expect(tampa.regionName) == "Tampa Bay"
                expect(tampa.versionInfo) == "1.1.11-SNAPSHOT|1|1|11|SNAPSHOT|6950d86123a7a9e5f12065bcbec0c516f35d86d9"
                expect(tampa.language) == "en_US"

                expect(tampa.supportsEmbeddedSocial).to(beTrue())
                expect(tampa.supportsOBADiscoveryAPIs).to(beTrue())
                expect(tampa.supportsOTPBikeshare).to(beTrue())
                expect(tampa.supportsSiriRealtimeAPIs).to(beTrue())
                expect(tampa.isActive).to(beTrue())
                expect(tampa.isExperimental).to(beFalse())

                expect(tampa.facebookURL).to(beNil())
                expect(tampa.contactEmail) == "onebusaway@gohart.org"
                expect(tampa.openTripPlannerContactEmail) == "otp-tampa@onebusaway.org"
                expect(tampa.twitterURL) == URL(string: "http://mobile.twitter.com/OBA_tampa")!

                expect(tampa.OBABaseURL) == URL(string: "http://api.tampa.onebusaway.org/api/")!
                expect(tampa.siriBaseURL) == URL(string: "http://tampa.onebusaway.org/onebusaway-api-webapp/siri/")!
                expect(tampa.openTripPlannerURL) == URL(string: "https://otp.prod.obahart.org/otp/")!
                expect(tampa.stopInfoURL).to(beNil())

                expect(tampa.paymentWarningBody).to(beNil())
                expect(tampa.paymentWarningTitle).to(beNil())
                expect(tampa.paymentAndroidAppID) == "co.bytemark.hart"
                expect(tampa.paymentiOSAppStoreIdentifier) == "1140553099"
                expect(tampa.paymentiOSAppURLScheme) == "fb313213768708402HART"

                let open311 = tampa.open311Servers.first!
                expect(open311.jurisdictionID).to(beNil())
                expect(open311.apiKey) == "937033cad3054ec58a1a8156dcdd6ad8a416af2f"
                expect(open311.baseURL) == URL(string: "https://seeclickfix.com/open311/v2/")!

                let bounds = tampa.regionBounds
                expect(bounds[0].lat).to(beCloseTo(27.976910500000002))
                expect(bounds[0].lon).to(beCloseTo(-82.445851))
                expect(bounds[0].latSpan).to(beCloseTo(0.5424609999999994))
                expect(bounds[0].lonSpan).to(beCloseTo(0.576357999999999))

                expect(bounds[1].lat).to(beCloseTo(27.919249999999998))
                expect(bounds[1].lon).to(beCloseTo(-82.652145))
                expect(bounds[1].latSpan).to(beCloseTo(0.47208000000000183))
                expect(bounds[1].lonSpan).to(beCloseTo(0.3967700000000036))

                let pugetSound = regions[1]

                expect(pugetSound.regionName) == "Puget Sound"

                let mapRect = MKMapRect(x: 42206703.270115554, y: 92590980.991902918, width: 1338771.0533083975, height: 1897888.1099742353)
                expect(pugetSound.serviceRect.minX) == mapRect.minX
                expect(pugetSound.serviceRect.minY) == mapRect.minY
                expect(pugetSound.serviceRect.maxX) == mapRect.maxX
                expect(pugetSound.serviceRect.maxY) == mapRect.maxY

                expect(pugetSound.centerCoordinate.latitude) == 47.795091214055
                expect(pugetSound.centerCoordinate.longitude) == -122.49868405298474

                done()
            }
        }
    }
}
