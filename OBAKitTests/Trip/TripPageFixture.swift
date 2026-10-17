//
//  TripPageFixture.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
import OBAKitCore
@testable import OBAKit

/// The recipe for a real `TripPageViewController`, shared by the suites that
/// exercise one.
///
/// `TripPageBackWiringTests` and `TripPageCollapseTests` both need a page built
/// against a real `Application` — one to resolve its Back row against a stack,
/// the other to drive its detent. They had the same three-argument construction
/// written out twice, so the next change to the initializer or to the arrival
/// fixture had to be made in both.
enum TripPageFixture {

    /// The screen the page was opened from. Any non-nil title does; it exists so
    /// the back row has something to render beside its button.
    static let originTitle = "3rd Ave & Pike St"

    @MainActor
    static func makePage(application: Application) throws -> TripPageViewController {
        TripPageViewController(
            application: application,
            tripConvertible: TripConvertible(arrivalDeparture: try Fixtures.arrivalDeparture()),
            originTitle: originTitle
        )
    }

    /// A page that can go on screen. `makePage`'s departure has no trip loaded,
    /// which the page reads once it appears; this one's does.
    @MainActor
    static func makeOnScreenPage(application: Application) throws -> TripPageViewController {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return TripPageViewController(
            application: application,
            arrivalDeparture: try #require(stopArrivals.arrivalsAndDepartures.first),
            originTitle: originTitle
        )
    }
}
