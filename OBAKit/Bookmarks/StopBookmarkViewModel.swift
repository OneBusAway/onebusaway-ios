//
//  StopBookmarkViewModel.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import Foundation
import OBAKitCore

struct StopBookmarkViewModel: Identifiable, Equatable {
    let id: String

    let name: String
    let stopID: StopID
    let primaryRouteType: Route.RouteType

    let isFavorite: Bool
}

#if DEBUG
extension StopBookmarkViewModel {
    static func preview(
        name: String,
        stopID: StopID,
        primaryRouteType: Route.RouteType,
        isFavorite: Bool
    ) -> Self {
        return self.init(
            id: UUID().uuidString,
            name: name,
            stopID: stopID,
            primaryRouteType: primaryRouteType,
            isFavorite: isFavorite)
    }

    static var soundTransitUDistrict: Self {
        return .preview(name: "U District", stopID: "990002", primaryRouteType: .lightRail, isFavorite: true)
    }

    static var ferrySeattle: Self {
        return .preview(name: "WSF Seattle", stopID: "7", primaryRouteType: .ferry, isFavorite: false)
    }
}
#endif
