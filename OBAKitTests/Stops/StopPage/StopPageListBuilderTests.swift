import XCTest
import OBAKitCore
@testable import OBAKit

private struct StubDeparture: DepartureListEntry {
    let id: String
    let routeID: RouteID
    let arrivalDepartureMinutes: Int
    var temporalState: TemporalState {
        arrivalDepartureMinutes < 0 ? .past : (arrivalDepartureMinutes == 0 ? .present : .future)
    }
}

private func dep(_ id: String, route: String, mins: Int) -> StubDeparture {
    StubDeparture(id: id, routeID: route, arrivalDepartureMinutes: mins)
}

@MainActor
final class StopPageListBuilderTests: XCTestCase {

    // MARK: - Chronological partition

    func test_partition_splitsAtWalkThreshold() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5), dep("c", route: "62", mins: 7)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        XCTAssertEqual(p.missed.map(\.id), ["a"])       // 1 < 4: can't reach on foot
        XCTAssertEqual(p.reachable.map(\.id), ["b", "c"]) // 5 and 7 >= 4 (§4.5: catchable iff mins >= walk)
        XCTAssertTrue(p.past.isEmpty)
    }

    func test_partition_boundaryIsCatchable() {
        // minutesAway == walkMinutes is catchable (§4.5: >=)
        let p = StopPageListBuilder.chronologicalPartition([dep("x", route: "5", mins: 4)], walkMinutes: 4)
        XCTAssertEqual(p.reachable.map(\.id), ["x"])
        XCTAssertTrue(p.missed.isEmpty)
    }

    func test_partition_nilWalk_hasNoMissedBucket() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        XCTAssertTrue(p.missed.isEmpty)
        XCTAssertEqual(p.reachable.map(\.id), ["a", "b"])
    }

    func test_partition_pastIsSeparateFromMissed() {
        // §4.2: past (already departed) and missed (can't walk there in time) are distinct.
        let deps = [dep("gone", route: "24", mins: -3), dep("miss", route: "H", mins: 1), dep("ok", route: "5", mins: 9)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        XCTAssertEqual(p.past.map(\.id), ["gone"])
        XCTAssertEqual(p.missed.map(\.id), ["miss"])
        XCTAssertEqual(p.reachable.map(\.id), ["ok"])
    }

    func test_partition_sortsByMinutes() {
        let deps = [dep("b", route: "1", mins: 9), dep("a", route: "2", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        XCTAssertEqual(p.reachable.map(\.id), ["a", "b"])
    }

    // MARK: - Route groups

    func test_groups_orderedBySoonestDeparture_notRouteName() {
        // §4.9: route with a bus in 1m outranks a route whose next is 5m.
        let deps = [
            dep("z5", route: "5", mins: 5), dep("h1", route: "H Line", mins: 1),
            dep("h2", route: "H Line", mins: 12), dep("z5b", route: "5", mins: 30)
        ]
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups.map(\.routeID), ["H Line", "5"])
        XCTAssertEqual(groups[0].departures.map(\.id), ["h1", "h2"])
        XCTAssertEqual(groups[0].next.id, "h1")
    }

    func test_groups_excludePastDepartures() {
        let deps = [dep("gone", route: "5", mins: -2), dep("soon", route: "5", mins: 6)]
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].departures.map(\.id), ["soon"])
    }

    func test_groups_chips_areAtMostThree_afterNext() {
        let deps = (0..<6).map { dep("d\($0)", route: "40", mins: 5 + $0 * 5) }
        let groups = StopPageListBuilder.routeGroups(deps)
        XCTAssertEqual(groups[0].chips.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(groups[0].upcoming.count, 5)
    }
}
