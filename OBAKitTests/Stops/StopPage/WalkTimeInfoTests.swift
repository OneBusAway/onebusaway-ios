import Testing
import CoreLocation
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class WalkTimeInfoTests {
    // ~111m per 0.001 degree latitude at the equator; use real CLLocations.
    private let stopLocation = CLLocation(latitude: 47.6097, longitude: -122.3331)

    @Test func `Computes minutes rounded up`() {
        // ~500m at 1.25 m/s = 400s = 6.67 min -> 7 min
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        let info = WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25)
        #expect(info != nil)
        #expect(info!.walkMinutes == 7)
    }

    @Test func `Nil when user location missing`() {
        #expect(WalkTimeInfo.compute(from: nil, to: stopLocation, speedMetersPerSecond: 1.25) == nil)
    }

    @Test func `Nil when very close`() {
        // <= 40m: suppress, matching today's WalkTimeView behavior.
        let user = CLLocation(latitude: 47.60972, longitude: -122.3331)
        #expect(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 1.25) == nil)
    }

    @Test func `Nil when speed invalid`() {
        let user = CLLocation(latitude: 47.6142, longitude: -122.3331)
        #expect(WalkTimeInfo.compute(from: user, to: stopLocation, speedMetersPerSecond: 0) == nil)
    }
}
