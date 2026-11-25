//
//  SheetCoordinatorTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import MapKit
@testable import OBAKit
@testable import OBAKitCore

/// Behavior tests for `SheetCoordinator`'s content-swap and stacked navigation,
/// using `AppSheetRoute` as the concrete `SheetRouteable` driver.
@MainActor
@Suite(.serialized)
final class SheetCoordinatorTests {

    // MARK: - Init

    @Test func `Init seeds route stack with root`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.canPop == false)
    }

    @Test func `Init sets current detent to root initial detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Init stacked layer starts empty`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
    }

    // MARK: - Push dispatches by prefersStacking

    @Test func `Push non stacking route appends content stack and resets detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.canPop == true)
        #expect(coordinator.currentDetent == AppSheetRoute.search.detentConfiguration.initialDetent)
    }

    @Test func `Push stacking route appends to stacked and leaves content stack alone`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)

        coordinator.push(.tripPlanner(TripPlannerRequest()))

        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes == [.tripPlanner(TripPlannerRequest())])
        #expect(coordinator.stackedDetents == [AppSheetRoute.tripPlanner(TripPlannerRequest()).detentConfiguration.initialDetent])
    }

    @Test func `Push stacking route stacks multiple sheets`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1_75403"))
        coordinator.push(trip)

        #expect(coordinator.stackedRoutes == [
            .recentStopsAll,
            .stopDetails(stopID: "1_75403"),
            trip
        ])
        #expect(coordinator.stackedDetents.count == 3)
    }

    // MARK: - All routes

    /// Base layer first, then the stacked sheets in the order they were pushed, so
    /// a check like "is this sheet still open?" sees both layers.
    @Test func `All routes lists the base stack and then the stacked sheets`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.stopDetails(stopID: "1_75403"))
        coordinator.push(.mapSettings)

        #expect(coordinator.allRoutes == [.home, .search, .stopDetails(stopID: "1_75403"), .mapSettings])
    }

    // MARK: - open(_:from:)

    /// A trip opened from the Stop sheet sits on top of it, so Back from the trip
    /// returns to the stop the rider came from.
    @Test func `Open from a sheet pushes on top of it, and pop returns to it`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(stop)

        coordinator.open(trip, from: stop)
        #expect(coordinator.stackedRoutes == [stop, trip])

        coordinator.pop()
        #expect(coordinator.stackedRoutes == [stop])
    }

    /// The sheet the tap came from has already closed: nothing below is touched,
    /// and the route still opens on top.
    @Test func `Open from a sheet no longer in the pile pushes on top`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(stop)

        coordinator.open(trip, from: .stopDetails(stopID: "1_99999"))

        #expect(coordinator.stackedRoutes == [stop, trip])
    }

    /// A tap in a sheet with another sheet over it, such as a departure on a Stop
    /// sheet under a half-height trip, replaces what was over it instead of
    /// stacking a second trip on the first.
    @Test func `Open from a covered sheet closes what was above it first`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let firstTrip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        let secondTrip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t2"))
        coordinator.push(stop)
        coordinator.push(firstTrip)

        coordinator.open(secondTrip, from: stop)

        #expect(coordinator.stackedRoutes == [stop, secondTrip])
    }

    /// Trip X, one of its stops, then trip X's departure at that stop: the trip is
    /// already open underneath, so the rider goes back to it instead of the tap
    /// doing nothing.
    @Test func `Open goes back to a route already open further down`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(stopID: "stop_1", tripID: "t1"))
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        coordinator.push(trip)
        coordinator.push(stop)

        coordinator.open(.tripDetails(try Fixtures.tripConvertible(stopID: "stop_2", tripID: "t1")), from: stop)

        #expect(coordinator.stackedRoutes == [trip])
    }

    @Test func `Open leaves a route already on top as it is`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(stop)
        coordinator.push(trip)
        coordinator.setStackedDetent(.large, at: 1)

        coordinator.open(trip, from: stop)

        #expect(coordinator.stackedRoutes == [stop, trip])
        #expect(coordinator.stackedDetents == [.medium, .large])
    }

    // MARK: - claimUnwindFocus(atDepth:)

    /// Stop, trip, another stop, then the first stop from that trip: three sheets
    /// close at once. The layer that closed them, the one hosted by the stop
    /// revealed, claims the focus move, and claims it once.
    @Test func `Going back further down is claimed once by the layer it closed`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(stop)
        coordinator.push(trip)
        coordinator.push(.stopDetails(stopID: "1_10914"))
        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t2")))

        coordinator.open(stop, from: coordinator.stackedRoutes[3])

        #expect(coordinator.stackedRoutes == [stop])
        // Layers above the one that closed sit on sheets that closed with it.
        #expect(coordinator.claimUnwindFocus(atDepth: 2) == false)
        #expect(coordinator.claimUnwindFocus(atDepth: 1))
        #expect(coordinator.claimUnwindFocus(atDepth: 1) == false)
    }

    /// A sheet the rider closes, or one an `open` replaces with a sheet of its own,
    /// leaves focus to UIKit, which returns it to the control that opened the sheet.
    @Test func `Only going back further down moves focus`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        coordinator.push(stop)
        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))

        coordinator.pop()
        #expect(coordinator.claimUnwindFocus(atDepth: 1) == false)

        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))
        coordinator.truncateStacked(toDepth: 1)
        #expect(coordinator.claimUnwindFocus(atDepth: 1) == false)

        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))
        coordinator.open(.tripDetails(try Fixtures.tripConvertible(tripID: "t2")), from: stop)
        #expect(coordinator.claimUnwindFocus(atDepth: 1) == false)
    }

    /// The route is already frontmost, so nothing closes and no dismissal would
    /// ever claim the move: left set, it would fire on an unrelated swipe later.
    @Test func `Going back to the frontmost sheet leaves nothing to claim`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t1"))
        coordinator.push(stop)
        coordinator.push(trip)

        coordinator.open(trip, from: stop)

        #expect(coordinator.unwindFocusDepth == nil)
    }

    /// A sheet opened, or the whole pile cleared, before the unwind's dismissal
    /// finishes: the new state owns focus, so the pending move is dropped.
    @Test func `A push or pop to root drops a pending unwind`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop = AppSheetRoute.stopDetails(stopID: "1_75403")
        coordinator.push(stop)
        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))

        coordinator.open(stop, from: coordinator.stackedRoutes[1])
        coordinator.push(.mapSettings)
        #expect(coordinator.unwindFocusDepth == nil)

        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))
        coordinator.open(stop, from: coordinator.stackedRoutes[2])
        coordinator.popToRoot()
        #expect(coordinator.unwindFocusDepth == nil)
    }

    // MARK: - isStackedSheetCovered(atDepth:)

    /// Only the frontmost stacked sheet can be swiped away. The rest have a sheet
    /// over them, and an index past the pile has nothing there to cover.
    @Test func `Every stacked sheet but the frontmost is covered`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.stopDetails(stopID: "1_75403"))
        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))
        coordinator.push(.mapSettings)

        #expect(coordinator.isStackedSheetCovered(atDepth: 0))
        #expect(coordinator.isStackedSheetCovered(atDepth: 1))
        #expect(coordinator.isStackedSheetCovered(atDepth: 2) == false)
        #expect(coordinator.isStackedSheetCovered(atDepth: 3) == false)
    }

    @Test func `A lone stacked sheet is not covered`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.isStackedSheetCovered(atDepth: 0) == false)

        coordinator.push(.mapSettings)
        #expect(coordinator.isStackedSheetCovered(atDepth: 0) == false)
    }

    // MARK: - Pop removes topmost layer

    @Test func `Pop with stacked presented removes top stacked and preserves content stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.pop()

        #expect(coordinator.stackedRoutes == [.tripPlanner(TripPlannerRequest())])
        #expect(coordinator.stackedDetents.count == 1)
        #expect(coordinator.routeStack.count == 2)
        #expect(coordinator.currentRoute == .search)
    }

    @Test func `Pop last stacked route empties stacked layer`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))

        coordinator.pop()

        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
    }

    @Test func `Pop without stacked removes top and restores previous initial detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.currentDetent = .medium

        coordinator.pop()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.canPop == false)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Pop at root is no op`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .large

        coordinator.pop()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.currentDetent == .large)
    }

    // MARK: - One sheet at a time

    /// A stop opened from an expanded home sheet sits over the collapsed search
    /// field, not over a second sheet of lists.
    @Test func `A stacked sheet rests the base sheet at its initial detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = AppSheetRoute.largeDetent

        coordinator.push(.stopDetails(stopID: "1_1"))

        #expect(coordinator.currentDetent == AppSheetRoute.homeCollapsedDetent)
    }

    @Test func `Closing the last stacked sheet puts the base sheet back`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .medium
        coordinator.push(.stopDetails(stopID: "1_1"))
        coordinator.push(.tripDetails(try Fixtures.tripConvertible(tripID: "t1")))

        coordinator.pop()
        #expect(coordinator.currentDetent == AppSheetRoute.homeCollapsedDetent, "Still covered")

        coordinator.pop()
        #expect(coordinator.currentDetent == .medium)
    }

    @Test func `A drag dismissal of the stacked layer puts the base sheet back`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = AppSheetRoute.largeDetent
        coordinator.push(.stopDetails(stopID: "1_1"))

        coordinator.truncateStacked(toDepth: 0)

        #expect(coordinator.currentDetent == AppSheetRoute.largeDetent)
    }

    @Test func `A collapsed base sheet stays collapsed through a stacked sheet`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.stopDetails(stopID: "1_1"))
        coordinator.pop()

        #expect(coordinator.currentDetent == AppSheetRoute.homeCollapsedDetent)
        #expect(coordinator.baseDetentBeforeStacking == nil)
    }

    @Test func `Going back to root forgets the base sheet's old detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .medium
        coordinator.push(.stopDetails(stopID: "1_1"))

        coordinator.popToRoot()

        #expect(coordinator.currentDetent == AppSheetRoute.homeCollapsedDetent)
        #expect(coordinator.baseDetentBeforeStacking == nil)
    }

    // MARK: - truncateStacked (OS-driven dismiss)

    @Test func `Truncate stacked removes everything at and above depth`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let trip = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "t"))
        coordinator.push(.recentStopsAll)
        coordinator.push(.stopDetails(stopID: "1"))
        coordinator.push(trip)

        coordinator.truncateStacked(toDepth: 1)

        #expect(coordinator.stackedRoutes == [.recentStopsAll])
        #expect(coordinator.stackedDetents.count == 1)
    }

    @Test func `Truncate stacked ignores out of range depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))

        coordinator.truncateStacked(toDepth: 5)

        #expect(coordinator.stackedRoutes == [.tripPlanner(TripPlannerRequest())])
    }

    // MARK: - setStackedDetent

    @Test func `Set stacked detent persists at given depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.setStackedDetent(.medium, at: 0)
        coordinator.setStackedDetent(.large, at: 1)

        #expect(coordinator.stackedDetents == [.medium, .large])
    }

    @Test func `Set stacked detent ignores out of range depth`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        let original = coordinator.stackedDetents

        coordinator.setStackedDetent(.medium, at: 5)

        #expect(coordinator.stackedDetents == original)
    }

    // MARK: - setStackedDetent(_:forTopmostRouteMatching:)

    /// The depth-free overload is what a sheet's own content can call: it knows which
    /// route it is, never where it sits in the pile.
    @Test func `Set stacked detent by predicate targets the topmost match`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        coordinator.push(.stopDetails(stopID: "1"))
        coordinator.push(.tripPlanner(TripPlannerRequest(viaPoint: CLLocationCoordinate2D(latitude: 1, longitude: 2))))

        let applied = coordinator.setStackedDetent(.large) { route in
            if case .tripPlanner = route { return true }
            return false
        }

        #expect(applied)
        // Depth 2, not depth 0: the topmost planner is the one on screen.
        #expect(coordinator.stackedDetents == [.medium, .medium, .large])
    }

    @Test func `Set stacked detent by predicate is a no op when nothing matches`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.stopDetails(stopID: "1"))
        let original = coordinator.stackedDetents

        let applied = coordinator.setStackedDetent(.medium) { route in
            if case .tripPlanner = route { return true }
            return false
        }

        #expect(applied == false)
        #expect(coordinator.stackedDetents == original)
    }

    /// `presentationDetents(_:selection:)` ignores a selection outside its set, so
    /// storing one would leave the coordinator disagreeing with the screen.
    @Test func `Set stacked detent by predicate refuses a detent the route does not declare`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        // Declares `.large` alone.
        coordinator.push(.nearbyAll)

        let applied = coordinator.setStackedDetent(.medium) { route in
            route == .nearbyAll
        }

        #expect(applied == false)
        #expect(coordinator.stackedDetents == [.large])
    }

    // MARK: - stackedRoute(at:) / stackedDetent(at:fallback:)

    @Test func `Stacked route at depth returns route when in range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        coordinator.push(.stopDetails(stopID: "1"))

        #expect(coordinator.stackedRoute(at: 0) == .tripPlanner(TripPlannerRequest()))
        #expect(coordinator.stackedRoute(at: 1) == .stopDetails(stopID: "1"))
    }

    @Test func `Stacked route at depth returns nil when out of range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedRoute(at: 0) == nil)

        coordinator.push(.tripPlanner(TripPlannerRequest()))
        #expect(coordinator.stackedRoute(at: 1) == nil)
    }

    @Test func `Stacked detent at depth returns stored detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.tripPlanner(TripPlannerRequest()))
        coordinator.setStackedDetent(.medium, at: 0)

        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == .medium)
    }

    @Test func `Stacked detent at depth returns fallback when out of range`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == .large)
    }

    // MARK: - canPop / popToRoot / currentDetents

    @Test func `Can pop is true when only stacked presented`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.canPop == false)

        coordinator.push(.tripPlanner(TripPlannerRequest()))
        #expect(coordinator.canPop == true)
    }

    @Test func `Pop to root clears stacked and unwinds content stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.search)
        coordinator.push(.nearbyAll)        // stacked
        coordinator.push(.recentStopsAll)   // also stacked

        coordinator.popToRoot()

        #expect(coordinator.routeStack.count == 1)
        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.stackedDetents.isEmpty)
        #expect(coordinator.canPop == false)
        #expect(coordinator.currentDetent == AppSheetRoute.home.detentConfiguration.initialDetent)
    }

    @Test func `Current detents reflects content stack top regardless of stacked`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        #expect(coordinator.currentDetents == AppSheetRoute.home.detentConfiguration.detents)

        coordinator.push(.search)
        #expect(coordinator.currentDetents == AppSheetRoute.search.detentConfiguration.detents)

        coordinator.push(.tripPlanner(TripPlannerRequest())) // stacked — must not alter currentDetents
        #expect(coordinator.currentDetents == AppSheetRoute.search.detentConfiguration.detents)
    }

    // MARK: - Search navigation shape

    /// Search content-swaps the base sheet; disambiguation stacks *over* it, so the
    /// search screen stays alive underneath and its query survives a Close.
    @Test func `Search results stack over the search route rather than replacing it`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let response = SearchResponse(request: SearchRequest(query: "44", type: .route), results: [], boundingRegion: nil, error: nil)

        coordinator.push(.search)
        coordinator.push(.searchResults(response))

        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.stackedRoutes.count == 1)
    }

    /// Picking a result unwinds search before opening the detail, so Close on the
    /// detail lands on home — not on a stale search screen.
    @Test func `Popping search after a result leaves home beneath the detail sheet`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        coordinator.push(.search)
        coordinator.pop()
        coordinator.push(.stopDetails(stopID: "1_75403"))

        #expect(coordinator.currentRoute == .home)
        #expect(coordinator.stackedRoutes == [.stopDetails(stopID: "1_75403")])
    }

    // MARK: - Stop sheets close themselves (#1751)

    /// The stop sheet locks interactive dismissal, so its Close button pops it
    /// through the coordinator. Pushing one must not trip a stacked-route invariant.
    @Test func `A stop sheet stacks although it locks interactive dismissal`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.stopDetails(stopID: "1"))
        #expect(coordinator.stackedRoutes == [.stopDetails(stopID: "1")])
    }

    /// Closing a stop opened over another stacked sheet returns to that sheet,
    /// and the pile matches what's on screen.
    @Test func `Closing a stop over another sheet returns to the sheet underneath`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.nearbyAll)
        coordinator.push(.stopDetails(stopID: "1"))

        coordinator.pop()

        #expect(coordinator.stackedRoutes == [.nearbyAll])
        #expect(coordinator.stackedEntries.count == 1)
    }

    /// A stop sheet's detent can be moved to its collapsed rung, which it declares.
    @Test func `A stop sheet can rest at its collapsed detent`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.push(.stopDetails(stopID: "1"))
        let moved = coordinator.setStackedDetent(AppSheetRoute.stopCollapsedDetent) { $0.isStopDetails }
        #expect(moved)
        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == AppSheetRoute.stopCollapsedDetent)
    }

    // MARK: - selectFromMap(_:)

    /// Selecting a map pin when the stack is empty pushes the route.
    @Test func `Select from map pushes route when stack is empty`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])
    }

    /// Tapping the exact same map pin again is a no-op and does not stack duplicate sheets.
    @Test func `Select from map ignores repeated tap on the same pin`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])
    }

    /// Tapping a different map pin opens over the current sheet.
    @Test func `Select from map opens a different pin over the current sheet`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let vehicle = AppSheetRoute.rentalDetail(rentalID: "v_1")

        coordinator.selectFromMap(stop1)
        coordinator.selectFromMap(vehicle)

        #expect(coordinator.stackedRoutes == [stop1, vehicle])
    }

    /// Tapping a pin for a route already lower in the stack unwinds back to that route.
    /// E.g. with [stop1, tripPlanner], selecting stop1 unwinds the stack back to [stop1].
    @Test func `Select from map unwinds to an existing route in the stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let tripPlanner = AppSheetRoute.tripPlanner(TripPlannerRequest())

        // Initial stack: [stop1, tripPlanner]
        coordinator.selectFromMap(stop1)
        coordinator.push(tripPlanner)
        #expect(coordinator.stackedRoutes == [stop1, tripPlanner])

        // Tapping stop1 pin unwinds the stack to stop1, closing trip planner
        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])
    }

    /// Full map pin selection sequence: stop1 -> vehicle -> cluster -> unwind to stop1 -> stop2.
    @Test func `Select from map handles handoff sequence and unwinding across multiple pins`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let stop2 = AppSheetRoute.stopDetails(stopID: "stop_2")
        let vehicle = AppSheetRoute.rentalDetail(rentalID: "v_1")
        let cluster = AppSheetRoute.rentalCluster(memberIDs: ["v_1", "v_2"])

        // 1. Initial stop
        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // 2. Repeated tap
        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // 3. Handoff to vehicle
        coordinator.selectFromMap(vehicle)
        #expect(coordinator.stackedRoutes == [stop1, vehicle])

        // 4. Handoff to cluster
        coordinator.selectFromMap(cluster)
        #expect(coordinator.stackedRoutes == [stop1, vehicle, cluster])

        // 5. Tap stop1 again -> unwinds back to stop1
        coordinator.selectFromMap(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // 6. Tap stop2 -> opens over stop1
        coordinator.selectFromMap(stop2)
        #expect(coordinator.stackedRoutes == [stop1, stop2])

        // 7. Pop to root
        coordinator.popToRoot()
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentRoute == .home)
    }

    // MARK: - restoreRoute(_:)

    /// Restoring a stop route when empty pushes the route with its initial detent.
    @Test func `Restore route pushes route with initial detent when stack is empty`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.restoreRoute(stop1)

        #expect(coordinator.stackedRoutes == [stop1])
        #expect(coordinator.stackedDetent(at: 0, fallback: .large) == stop1.detentConfiguration.initialDetent)
        #expect(coordinator.currentRoute == .home)
    }

    /// Calling restoreRoute repeatedly is idempotent and does not duplicate sheets.
    @Test func `Restore route is idempotent and does not duplicate on repeated calls`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.restoreRoute(stop1)
        coordinator.restoreRoute(stop1)
        coordinator.restoreRoute(stop1)

        #expect(coordinator.stackedRoutes == [stop1])
        #expect(coordinator.stackedDetents == [stop1.detentConfiguration.initialDetent])
    }

    /// Repeated dismissal via pop or truncate leaves the coordinator in a clean state, and subsequent restoration succeeds.
    @Test func `Repeated dismissal leaves stack empty and subsequent restoration succeeds`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // Dismiss repeatedly
        coordinator.pop()
        #expect(coordinator.stackedRoutes.isEmpty)

        coordinator.pop()
        #expect(coordinator.stackedRoutes.isEmpty)

        coordinator.truncateStacked(toDepth: 0)
        #expect(coordinator.stackedRoutes.isEmpty)

        coordinator.popToRoot()
        #expect(coordinator.stackedRoutes.isEmpty)

        // Restoring after repeated dismissal cleanly presents the stop
        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])
    }

    /// Dismissing multiple stacked sheets and restoring returns to a stable state with proper base sheet restoration.
    @Test func `Dismissing multiple stacked sheets and restoring returns to stable state`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        coordinator.currentDetent = .medium // rider expanded home before stacking

        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let trip1 = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "trip_1"))

        coordinator.restoreRoute(stop1)
        coordinator.restoreRoute(trip1)
        #expect(coordinator.stackedRoutes == [stop1, trip1])

        // Dismiss top trip
        coordinator.pop()
        #expect(coordinator.stackedRoutes == [stop1])

        // Dismiss stop
        coordinator.pop()
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentDetent == .medium) // base sheet detent restored

        // Dismiss again (repeated dismissal)
        coordinator.pop()
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentDetent == .medium)

        // Restore stop1 again
        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        coordinator.pop()
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentDetent == .medium)
    }

    /// Restoring an already open route preserves presentation without duplicate.
    @Test func `Restoring already open route preserves presentation without duplicate`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.restoreRoute(stop1)
        coordinator.setStackedDetent(.large, at: 0)
        #expect(coordinator.stackedDetent(at: 0, fallback: .medium) == .large)

        // Same stop restored
        coordinator.restoreRoute(stop1)

        #expect(coordinator.stackedRoutes == [stop1])
        // Preserves current presentation detent instead of resetting to initial
        #expect(coordinator.stackedDetent(at: 0, fallback: .medium) == .large)
    }

    /// Restoring stop with transfer context matches plain stop route identity.
    @Test func `Restoring stop with transfer context matches plain stop route identity`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let plain = AppSheetRoute.stopDetails(stopID: "stop_1")
        let context = TransferContext(
            arrivalTime: Date(timeIntervalSince1970: 1_700_000_000),
            fromRouteShortName: "7",
            fromTripHeadsign: "Downtown",
            fromTripID: "trip_7"
        )
        let withContext = AppSheetRoute.stopDetails(stopID: "stop_1", transferContext: context)

        coordinator.restoreRoute(plain)
        #expect(coordinator.stackedRoutes == [plain])

        // Carries transferContext but same stopID
        coordinator.restoreRoute(withContext)

        // Route identity matches: no duplicate sheet presented
        #expect(coordinator.stackedRoutes.count == 1)
        #expect(coordinator.stackedRoutes.first?.id == plain.id)
    }

    /// Restoring route unwinds higher sheets back to the target route.
    @Test func `Restoring route unwinds higher sheets back to target route`() throws {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let stop2 = AppSheetRoute.stopDetails(stopID: "stop_2")
        let trip1 = AppSheetRoute.tripDetails(try Fixtures.tripConvertible(tripID: "trip_1"))

        coordinator.restoreRoute(stop1)
        coordinator.restoreRoute(trip1)
        coordinator.restoreRoute(stop2)
        #expect(coordinator.stackedRoutes == [stop1, trip1, stop2])

        // Unwinds back to stop1
        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])
    }

    /// Restoring route presents new destination over existing stack.
    @Test func `Restoring route presents new destination over existing stack`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")
        let stop2 = AppSheetRoute.stopDetails(stopID: "stop_2")

        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // Stop2 arrives
        coordinator.restoreRoute(stop2)
        #expect(coordinator.stackedRoutes == [stop1, stop2])

        // Rapid duplicate does not duplicate
        coordinator.restoreRoute(stop2)
        #expect(coordinator.stackedRoutes == [stop1, stop2])
    }

    /// Restore route with content-swap route unwinds and preserves single state.
    @Test func `Restore route with content swap route unwinds and preserves single state`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        coordinator.restoreRoute(.search)
        #expect(coordinator.currentRoute == .search)
        #expect(coordinator.routeStack == [.home, .search])

        // Stacking over search
        coordinator.restoreRoute(stop1)
        #expect(coordinator.stackedRoutes == [stop1])

        // Restoring search clears stacked layer and keeps search as current
        coordinator.restoreRoute(.search)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentRoute == .search)

        // Restoring home pops to root
        coordinator.restoreRoute(.home)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentRoute == .home)
    }

    /// Restoring the current base route while stacked sheets are open unwinds stacked sheets
    /// and preserves the base sheet's saved detent instead of resetting it to initialDetent.
    @Test func `Restore route preserves base sheet detent when unwinding stacked sheets over current base route`() {
        // No app route is a non-root base sheet with more than one detent, so a
        // stand-in exercises the path.
        let coordinator = SheetCoordinator<BaseAndDetailRoute>(root: .root)

        // Push non-stacking base route with initial detent .large
        coordinator.push(.base)
        #expect(coordinator.currentRoute == .base)
        #expect(coordinator.currentDetent == .large)

        // Change detent to .medium
        coordinator.currentDetent = .medium

        // Stacking over base route rests base sheet and saves its detent (.medium)
        coordinator.push(.detail)
        #expect(coordinator.stackedRoutes == [.detail])

        // Restoring .base uncovers base route and restores its saved detent
        coordinator.restoreRoute(.base)
        #expect(coordinator.stackedRoutes.isEmpty)
        #expect(coordinator.currentRoute == .base)
        #expect(coordinator.currentDetent == .medium)
    }

    /// Restoring a route that is already on top does not clear lastChangeWasPopToRoot.
    @Test func `Restore route does not clear lastChangeWasPopToRoot on no-op early return`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)

        // Pop to root sets flag
        coordinator.push(.search)
        coordinator.popToRoot()
        #expect(coordinator.lastChangeWasPopToRoot)

        // Restoring .home when already at root leaves flag true
        coordinator.restoreRoute(.home)
        #expect(coordinator.lastChangeWasPopToRoot)
    }

    /// One input yields one stable state regardless of repetition.
    @Test func `One input yields one stable state across repeated invocations`() {
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let stop1 = AppSheetRoute.stopDetails(stopID: "stop_1")

        // Repeating 5 times produces identical stable state
        for _ in 0..<5 {
            coordinator.restoreRoute(stop1)
            #expect(coordinator.stackedRoutes == [stop1])
            #expect(coordinator.stackedDetents.count == 1)
        }
    }
}

/// A root, a non-stacking base sheet that opens large and can be dragged to medium,
/// and a stacked detail.
private nonisolated enum BaseAndDetailRoute: String, SheetRouteable {
    case root, base, detail

    var id: String { rawValue }

    var detentConfiguration: SheetDetentConfiguration {
        SheetDetentConfiguration(detents: [.medium, .large], initialDetent: self == .root ? .medium : .large, isDismissDisabled: false)
    }

    var prefersStacking: Bool { self == .detail }

    var sheetBackground: SheetBackground { .plain }
}
