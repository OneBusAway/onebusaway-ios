//
//  TripBookmarkViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/5/21.
//

import SwiftUI
import OBAKitCore

struct TripBookmarkViewModel: Identifiable, Equatable {
    let id: String

    let name: String
    let stopID: StopID

    let isFavorite: Bool
    let routeShortName: String?
    let tripHeadsign: String?
    let routeID: RouteID?
    let routeType: Route.RouteType

    let isLoading: Bool

    var primaryArrivalDeparture: DepartureTimeViewModel?
    var secondaryArrivalDeparture: DepartureTimeViewModel?
    var tertiaryArrivalDeparture: DepartureTimeViewModel?

    static func fromBookmark(bookmark: Bookmark, isLoading: Bool) -> Self {
        return self.init(id: bookmark.id.uuidString, name: bookmark.name, stopID: bookmark.stopID, isFavorite: bookmark.isFavorite, routeShortName: bookmark.routeShortName, tripHeadsign: bookmark.tripHeadsign, routeID: bookmark.routeID, routeType: .unknown, isLoading: isLoading, primaryArrivalDeparture: nil, secondaryArrivalDeparture: nil, tertiaryArrivalDeparture: nil)
    }
}

#if DEBUG
extension TripBookmarkViewModel {
    static func preview(
        name: String,
        stopID: StopID,
        routeType: Route.RouteType,
        routeShortName: String?,
        isFavorite: Bool,
        primaryArrivalDeparture: DepartureTimeViewModel? = nil,
        secondaryArrivalDeparture: DepartureTimeViewModel? = nil,
        tertiaryArrivalDeparture: DepartureTimeViewModel? = nil
    ) -> Self {
        return self.init(
            id: UUID().uuidString,
            name: name,
            stopID: stopID,
            isFavorite: isFavorite,
            routeShortName: routeShortName,
            tripHeadsign: nil,
            routeID: nil,
            routeType: routeType,
            isLoading: false,
            primaryArrivalDeparture: primaryArrivalDeparture,
            secondaryArrivalDeparture: secondaryArrivalDeparture,
            tertiaryArrivalDeparture: tertiaryArrivalDeparture)
    }

    static var linkArrivingNowOnTime: TripBookmarkViewModel {
        let arrDep1 = DepartureTimeViewModel.DEBUG_departingNOWOnTime
        let arrDep2 = DepartureTimeViewModel.DEBUG_departingIn20MinutesScheduled
        let arrDep3 = DepartureTimeViewModel.DEBUG_arrivingIn124MinutesScheduled
        return .preview(name: "[N] Link CapHill", stopID: "1_faskdfjlh", routeType: .lightRail, routeShortName: "1-Line", isFavorite: true, primaryArrivalDeparture: arrDep1, secondaryArrivalDeparture: arrDep2, tertiaryArrivalDeparture: arrDep3)
    }

    static var metroTransitBLineDepartingLate: TripBookmarkViewModel {
        let arrDep1 = DepartureTimeViewModel.DEBUG_arrivingIn3MinutesLate
        return .preview(name: "NE 8th St & 143rd Ave NE", stopID: "1_fdsf", routeType: .bus, routeShortName: "B Line", isFavorite: true, primaryArrivalDeparture: arrDep1, secondaryArrivalDeparture: nil, tertiaryArrivalDeparture: nil)
    }

    static var soundTransit550NoTrips: TripBookmarkViewModel {
        return .preview(name: "Bellevue Transit Center - Bay 9", stopID: "1_1asdf", routeType: .bus, routeShortName: "550", isFavorite: false, primaryArrivalDeparture: nil, secondaryArrivalDeparture: nil, tertiaryArrivalDeparture: nil)
    }
}
#endif
