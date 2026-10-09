//
//  TripFocusMapDisplayModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import SwiftUI
import OBAKitCore

/// What the panel's map draws for an open trip sheet, and where the camera goes
/// when that trip first draws.
///
/// The panel's counterpart of `TripFocusMapLayer`, which draws on an `MKMapView`
/// the panel doesn't have. Both read the trip page's `TripMapFocus`, and both take
/// the split, the vehicle's position and the framing from `TripMapFocus.Content`.
@MainActor
final class TripFocusMapDisplayModel: ObservableObject {

    /// Everything the map builder needs, resolved once per update rather than in
    /// `body`, which re-runs on every sheet-height change while a sheet is dragged.
    /// Same reason as `MapSearchDisplayModel.RouteDisplay`.
    struct Display {
        let routeColor: Color
        /// Behind the vehicle. `nil` when less than two points of the shape are.
        let spent: ShapeLine?
        /// Ahead of the vehicle. `nil` when less than two points of the shape are.
        let ahead: ShapeLine?
        /// Along the part still ahead, as `TripFocusMapLayer` places them.
        let arrows: [PolylineArrowPlacement]
        let stops: [TripStop]
        let vehicle: TripVehicle?

        fileprivate var isEmpty: Bool {
            spent == nil && ahead == nil && stops.isEmpty && vehicle == nil
        }
    }

    /// One half of the shape, as the white casing and the colored core drawn over
    /// it. Two polylines rather than one stroked twice, matching the separate
    /// overlays `TripFocusMapLayer` adds for each.
    struct ShapeLine {
        let casing: MKPolyline
        let core: MKPolyline
    }

    struct TripStop: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let isPassed: Bool
        let isUserStop: Bool
        let isTerminal: Bool
    }

    struct TripVehicle {
        let coordinate: CLLocationCoordinate2D
        let routeType: Route.RouteType
        let isRealTime: Bool
        /// In degrees, as OBA reports it.
        let orientation: CLLocationDirection
    }

    /// Where the camera should move. One-shot, like `MapSearchDisplayModel.cameraTarget`:
    /// the view applies it and calls `consumeCameraTarget()`.
    ///
    /// The rect carries no insets: room for the sheet depends on the map's size,
    /// which only the view knows, so the view pads it when it applies it.
    struct CameraTarget: Equatable {
        let rect: MKMapRect

        static func == (lhs: CameraTarget, rhs: CameraTarget) -> Bool {
            lhs.rect.origin.x == rhs.rect.origin.x && lhs.rect.origin.y == rhs.rect.origin.y
                && lhs.rect.size.width == rhs.rect.size.width && lhs.rect.size.height == rhs.rect.size.height
        }
    }

    @Published private(set) var display: Display?
    @Published private(set) var cameraTarget: CameraTarget?

    /// While a trip is drawn the ambient stop pins stand down, as they do for a
    /// planned trip or a searched route: the trip's own stops are drawn instead.
    var isShowingTrip: Bool { display != nil }

    /// The trip sheet whose trip is drawn. Its lifetime is the route stack's, for the
    /// reason `MapSearchDisplayModel.owner` gives; see `clearIfOwnerAbsent(from:)`.
    ///
    /// One trip, not a stack of them, because only one trip sheet is ever open:
    /// `MapPanelRootController.TripPresentationBridge` is the only thing that opens
    /// one, and it unwinds to the home sheet first.
    private(set) var owner: AppSheetRoute?

    /// Weak because the trip page owns it. The drawing ends with the page's sheet,
    /// not with this reference.
    private weak var focus: TripMapFocus?

    private var focusCancellable: AnyCancellable?

    /// The trip the camera was last framed for. Framing happens once per trip, as
    /// in `TripFocusMapLayer`: the position updates every 30s, and re-framing on
    /// each one would snatch the map back from a rider who had panned.
    private var framedTripID: String?

    /// The rider's location for framing, or `nil` when the app may not use it.
    private let userLocation: () -> CLLocationCoordinate2D?

    init(userLocation: @escaping () -> CLLocationCoordinate2D?) {
        self.userLocation = userLocation
    }

    /// Draws the trip `focus` describes, for as long as `owner` is on the sheet
    /// stack.
    func show(focus: TripMapFocus, owner: AppSheetRoute) {
        // The page reports its focus every time it appears, including on the way
        // back from a sheet it presented over itself. Starting over then would
        // re-frame a camera the rider may have moved.
        guard focus !== self.focus else { return }

        self.focus = focus
        self.owner = owner
        focusCancellable = focus.$content.sink { [weak self] content in
            self?.render(content)
        }
    }

    /// Drops the drawing once its trip sheet is no longer anywhere on the stack.
    /// Called on every change to that stack, so a drag-down, a Back tap and a
    /// `popToRoot` all end it the same way.
    ///
    /// The trip page isn't asked instead. It sends a `nil` focus from
    /// `viewWillDisappear` only when `isMovingFromParent`, a navigation-stack signal
    /// that says nothing reliable about a page hosted in a SwiftUI sheet.
    ///
    /// - Parameter routes: Every route on screen, on both sheet layers; see
    ///   `SheetCoordinator.allRoutes`.
    func clearIfOwnerAbsent(from routes: [AppSheetRoute]) {
        guard let owner, !routes.contains(owner) else { return }
        clear()
    }

    func clear() {
        owner = nil
        focus = nil
        focusCancellable = nil
        framedTripID = nil
        display = nil
        cameraTarget = nil
    }

    func consumeCameraTarget() {
        cameraTarget = nil
    }

    // MARK: - Rendering

    private func render(_ content: TripMapFocus.Content?) {
        guard let content else {
            display = nil
            return
        }

        let split = content.shapeSplit
        let display = Display(
            routeColor: Color(uiColor: content.routeColor),
            spent: Self.shapeLine(split.spent),
            ahead: Self.shapeLine(split.ahead),
            arrows: PolylineDirectionArrows.placements(along: split.ahead),
            // A stop whose location the feed omits costs one dot, not the trip.
            stops: content.stops.compactMap { row in
                row.coordinate.map {
                    TripStop(
                        id: row.id,
                        name: row.name,
                        coordinate: $0,
                        // As `TripStopAnnotation` draws it: the stop the bus is at
                        // isn't behind it yet.
                        isPassed: row.isPassed && !row.isVehicleHere,
                        isUserStop: row.isUserStop,
                        isTerminal: row.isTerminal
                    )
                }
            },
            vehicle: Self.vehicle(content)
        )

        // The page publishes its focus before the trip has loaded, with nothing in
        // it to draw. Counting that as a drawn trip would hide the ambient stops
        // for nothing, and for good if the trip never loads.
        self.display = display.isEmpty ? nil : display

        guard framedTripID != content.tripID,
              let rect = content.framingRect(split: split, userLocation: userLocation()) else { return }

        framedTripID = content.tripID
        cameraTarget = CameraTarget(rect: rect)
    }

    /// One point is not a line, and drawing it would add polylines that render as
    /// nothing.
    private static func shapeLine(_ coordinates: [CLLocationCoordinate2D]) -> ShapeLine? {
        guard coordinates.count >= 2 else { return nil }
        return ShapeLine(
            casing: MKPolyline(coordinates: coordinates, count: coordinates.count),
            core: MKPolyline(coordinates: coordinates, count: coordinates.count)
        )
    }

    private static func vehicle(_ content: TripMapFocus.Content) -> TripVehicle? {
        guard let status = content.vehicle, let coordinate = content.vehicleCoordinate else { return nil }
        return TripVehicle(
            coordinate: coordinate,
            routeType: content.routeType,
            isRealTime: status.isRealTime,
            orientation: status.orientation
        )
    }
}
