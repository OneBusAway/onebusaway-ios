import XCTest
import CoreLocation
@testable import OBAKit

@MainActor
final class WalkTimeInfoTests: XCTestCase {
    // ~111m per 0.001 degree latitude at the equator; use real CLLocations.
    private let stopLocation = CLLocation(latitude: 47.6097, longitude: -122.3331)

    func test_computesMinutesRoundedUp() {
        // ~500m at 1.25 m/s = 400s = 6.67 min -> 7 min
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        let info = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25)
        XCTAssertNotNil(info)
        XCTAssertEqual(info!.walkMinutes, 7)
    }

    func test_nilWhenUserLocationMissing() {
        XCTAssertNil(WalkTimeInfo.compute(from: nil, to: stopLocation, speedMetersPerSecond: 1.25))
    }

    func test_nilWhenVeryClose() {
        // <= 40m: suppress, matching today's WalkTimeView behavior.
        let user = CLLocation(latitude: 47.60972, longitude: -122.3331)
        XCTAssertNil(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25))
    }

    func test_nilWhenSpeedInvalid() {
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        XCTAssertNil(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 0))
    }
}
