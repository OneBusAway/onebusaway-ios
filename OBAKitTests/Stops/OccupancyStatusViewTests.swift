//
//  OccupancyStatusViewTests.swift
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

/// The occupancy row in the UIKit arrival rows (`StopArrivalView`), shown on the Report
/// Problem screen. `OccupancyBadgeTests` covers the SwiftUI badge the stop page uses.
@Suite(.serialized)
struct OccupancyStatusViewTests {

    // MARK: - Helpers

    private static let personImage = UIImage(systemName: "person.fill")
    private static let noPassengersImage = UIImage(systemName: "person.crop.circle.fill.badge.xmark")

    private func configured(_ status: ArrivalDeparture.OccupancyStatus, realtime: Bool = true) -> OccupancyStatusView {
        let view = OccupancyStatusView()
        view.configure(occupancyStatus: status, realtimeData: realtime)
        return view
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// Whether `view` and every ancestor up to `root` are shown.
    private func isShown(_ view: UIView, in root: UIView) -> Bool {
        var current: UIView? = view
        while let v = current, v !== root {
            if v.isHidden { return false }
            current = v.superview
        }
        return true
    }

    private func shownImageViews(in view: OccupancyStatusView, showing image: UIImage?) -> [UIImageView] {
        descendants(of: view)
            .compactMap { $0 as? UIImageView }
            .filter { $0.image == image && isShown($0, in: view) }
    }

    private func personCount(_ view: OccupancyStatusView) -> Int {
        shownImageViews(in: view, showing: Self.personImage).count
    }

    private func showsNoPassengersBadge(_ view: OccupancyStatusView) -> Bool {
        !shownImageViews(in: view, showing: Self.noPassengersImage).isEmpty
    }

    private func descriptionText(_ view: OccupancyStatusView) -> String? {
        descendants(of: view).compactMap { $0 as? UILabel }.first?.text
    }

    // MARK: - Status buckets

    @Test func `A fuller vehicle shows more people`() {
        let expected: [(ArrivalDeparture.OccupancyStatus, Int)] = [
            (.empty, 1),
            (.manySeatsAvailable, 1),
            (.fewSeatsAvailable, 2),
            (.standingRoomOnly, 2),
            (.crushedStandingRoomOnly, 3),
            (.full, 3)
        ]

        for (status, people) in expected {
            let view = configured(status)
            #expect(personCount(view) == people, "\(status)")
            #expect(!showsNoPassengersBadge(view), "\(status)")
            #expect(!view.isHidden, "\(status)")
        }
    }

    @Test func `A vehicle not taking passengers shows the no-passengers badge and no people`() {
        for status in [ArrivalDeparture.OccupancyStatus.notAcceptingPassengers, .notBoardable] {
            let view = configured(status)
            #expect(showsNoPassengersBadge(view), "\(status)")
            #expect(personCount(view) == 0, "\(status)")
        }
    }

    @Test func `An unknown occupancy hides the whole row`() {
        #expect(configured(.unknown).isHidden)
    }

    // MARK: - Historical data

    @Test func `Historical occupancy is labelled as historical and drawn dimmer than real-time`() throws {
        let realtime = configured(.standingRoomOnly, realtime: true)
        let historical = configured(.standingRoomOnly, realtime: false)

        let realtimeText = try #require(descriptionText(realtime))
        let historicalText = try #require(descriptionText(historical))
        #expect(historicalText != realtimeText)
        #expect(historicalText.contains(realtimeText))

        #expect(realtime.tintColor == .label)
        #expect(historical.tintColor == .secondaryLabel)

        // The people shown don't depend on where the data came from.
        #expect(personCount(historical) == personCount(realtime))
    }

    // MARK: - Reuse

    @Test func `A reused row shows only the people for its new status`() {
        let view = configured(.full)
        #expect(personCount(view) == 3)

        view.prepareForReuse()
        view.configure(occupancyStatus: .manySeatsAvailable, realtimeData: true)

        #expect(personCount(view) == 1)
    }

    @Test func `A reused row drops the no-passengers badge and comes back from hidden`() {
        let notTaking = configured(.notAcceptingPassengers)
        notTaking.prepareForReuse()
        notTaking.configure(occupancyStatus: .fewSeatsAvailable, realtimeData: true)

        #expect(!showsNoPassengersBadge(notTaking))
        #expect(personCount(notTaking) == 2)

        let unknown = configured(.unknown)
        #expect(unknown.isHidden)
        unknown.prepareForReuse()
        unknown.configure(occupancyStatus: .empty, realtimeData: true)

        #expect(!unknown.isHidden)
        #expect(personCount(unknown) == 1)
    }
}
