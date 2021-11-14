//
//  StopPreferencesViewModels.swift
//  OBAKit
//
//  Created by Alan Chu on 11/14/21.
//

import SwiftUI
import OBAKitCore

struct StopPreferencesRouteViewModel: Identifiable, Hashable, Equatable {
    let id: RouteID
    let displayName: String
    let agencyName: String

    init(id: RouteID, displayName: String, agencyName: String) {
        self.id = id
        self.displayName = displayName
        self.agencyName = agencyName
    }

    init(_ route: Route) {
        self.id = route.id
        self.displayName = route.longName ?? route.shortName
        self.agencyName = route.agency.name
    }
}

struct StopPreferencesViewModel {
    let stopID: StopID

    let availableRoutes: [StopPreferencesRouteViewModel]
    var selectedRoutes: Set<RouteID>

    // helper.
    fileprivate var availableRouteIDs: Set<RouteID> {
        return Set(availableRoutes.map { $0.id })
    }

    var hiddenRoutes: Set<RouteID> {
        get {
            return availableRouteIDs.subtracting(selectedRoutes)
        } set {
            selectedRoutes = availableRouteIDs.subtracting(newValue)
        }
    }

    init(stopID: StopID, availableRoutes: [StopPreferencesRouteViewModel], selectedRoutes: Set<RouteID> = []) {
        self.stopID = stopID
        self.availableRoutes = availableRoutes
        self.selectedRoutes = selectedRoutes
    }

    init(_ stop: Stop) {
        self.stopID = stop.id
        self.availableRoutes = stop.routes.localizedCaseInsensitiveSort().map(StopPreferencesRouteViewModel.init)
        self.selectedRoutes = Set<RouteID>(availableRoutes.map { $0.id })
    }
}
