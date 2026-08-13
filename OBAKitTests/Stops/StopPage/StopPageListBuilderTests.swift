import Testing
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
@Suite(.serialized)
final class StopPageListBuilderTests {

    // MARK: - Chronological partition

    @Test func `Partition splits at walk threshold`() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5), dep("c", route: "62", mins: 7)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        #expect(p.missed.map(\.id) == ["a"])       // 1 < 4: can't reach on foot
        #expect(p.reachable.map(\.id) == ["b", "c"]) // 5 and 7 >= 4 (§4.5: catchable iff mins >= walk)
        #expect(p.past.isEmpty)
    }

    @Test func `Partition boundary is catchable`() {
        // minutesAway == walkMinutes is catchable (§4.5: >=)
        let p = StopPageListBuilder.chronologicalPartition([dep("x", route: "5", mins: 4)], walkMinutes: 4)
        #expect(p.reachable.map(\.id) == ["x"])
        #expect(p.missed.isEmpty)
    }

    @Test func `Partition nil walk has no missed bucket`() {
        let deps = [dep("a", route: "H", mins: 1), dep("b", route: "132", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        #expect(p.missed.isEmpty)
        #expect(p.reachable.map(\.id) == ["a", "b"])
    }

    @Test func `Partition past is separate from missed`() {
        // §4.2: past (already departed) and missed (can't walk there in time) are distinct.
        let deps = [dep("gone", route: "24", mins: -3), dep("miss", route: "H", mins: 1), dep("ok", route: "5", mins: 9)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: 4)
        #expect(p.past.map(\.id) == ["gone"])
        #expect(p.missed.map(\.id) == ["miss"])
        #expect(p.reachable.map(\.id) == ["ok"])
    }

    @Test func `Partition sorts by minutes`() {
        let deps = [dep("b", route: "1", mins: 9), dep("a", route: "2", mins: 5)]
        let p = StopPageListBuilder.chronologicalPartition(deps, walkMinutes: nil)
        #expect(p.reachable.map(\.id) == ["a", "b"])
    }

    // MARK: - Route groups

    @Test func `Groups ordered by soonest departure not route name`() {
        // §4.9: route with a bus in 1m outranks a route whose next is 5m.
        let deps = [
            dep("z5", route: "5", mins: 5), dep("h1", route: "H Line", mins: 1),
            dep("h2", route: "H Line", mins: 12), dep("z5b", route: "5", mins: 30)
        ]
        let groups = StopPageListBuilder.routeGroups(deps)
        #expect(groups.map(\.routeID) == ["H Line", "5"])
        #expect(groups[0].departures.map(\.id) == ["h1", "h2"])
        #expect(groups[0].next.id == "h1")
    }

    @Test func `Groups exclude past departures`() {
        let deps = [dep("gone", route: "5", mins: -2), dep("soon", route: "5", mins: 6)]
        let groups = StopPageListBuilder.routeGroups(deps)
        #expect(groups.count == 1)
        #expect(groups[0].departures.map(\.id) == ["soon"])
    }

    @Test func `Groups chips are at most three after next`() {
        let deps = (0..<6).map { dep("d\($0)", route: "40", mins: 5 + $0 * 5) }
        let groups = StopPageListBuilder.routeGroups(deps)
        #expect(groups[0].chips.map(\.id) == ["d1", "d2", "d3"])
        #expect(groups[0].upcoming.count == 5)
    }
}
