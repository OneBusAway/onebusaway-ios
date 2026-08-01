import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class StopMapFocusTests {

    private func route(_ id: RouteID, live: Bool) -> StopRouteFocusModel.DrawnRoute {
        StopRouteFocusModel.DrawnRoute(
            routeID: id, shortName: id, color: .systemBlue, shapeID: "s_\(id)", hasLiveVehicle: live
        )
    }

    @Test func `Toggling a live route focuses it`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Toggling the same route twice clears focus`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.toggleFocus(routeID: "H")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `A route with no live vehicle is a no-op`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("40", live: false)])
        focus.toggleFocus(routeID: "40")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `An unknown route is a no-op`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "999")
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `A no-op toggle leaves existing focus intact`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true), route("40", live: false)])
        focus.toggleFocus(routeID: "H")
        focus.toggleFocus(routeID: "40")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focusing an already-focused route leaves it focused`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.focus(routeID: "H")
        focus.focus(routeID: "H")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focusing a route with no live vehicle is a no-op`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true), route("40", live: false)])
        focus.focus(routeID: "H")
        focus.focus(routeID: "40")
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focus drops when its route leaves the arrival set`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true), route("62", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("62", live: true)])
        #expect(focus.focusedRouteID == nil)
    }

    @Test func `Focus survives a refresh that keeps the route`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("H", live: true), route("62", live: true)])
        #expect(focus.focusedRouteID == "H")
    }

    @Test func `Focus drops when its route loses its last live vehicle`() {
        let focus = StopMapFocus()
        focus.apply(routes: [route("H", live: true)])
        focus.toggleFocus(routeID: "H")
        focus.apply(routes: [route("H", live: false)])
        #expect(focus.focusedRouteID == nil)
    }
}
