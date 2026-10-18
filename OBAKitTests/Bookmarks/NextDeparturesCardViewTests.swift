//
//  NextDeparturesCardViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The Next Departures card's layout (#1554).
@MainActor
@Suite(.serialized)
struct NextDeparturesCardViewTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fullCard() -> NextDeparturesCardModel {
        let departures = [(4.0, ScheduleStatus.onTime, 0), (11, .delayed, 6), (19, .early, -2)].map { minutes, status, deviation in
            NextDeparturesSummary.Departure(date: now.addingTimeInterval(minutes * 60), isRealTime: true, scheduleStatus: status, deviationMinutes: deviation)
        }
        return NextDeparturesCardModel(outcome: .departures(
            bookmarkName: "Home from the office, the long way around the lake",
            routeShortName: "C Line",
            headsign: "West Seattle Alaska Junction via Downtown and the Viaduct",
            departures: departures
        ), now: now)
    }

    /// Two buttons, as the card has with Refresh and Track.
    private func view(_ model: NextDeparturesCardModel) -> some View {
        NextDeparturesCardView(model: model) {
            Button("Refresh") {}
            Button("Track") {}
        }
    }

    /// The HIG caps a snippet's custom view at 400 pt. A full card at the
    /// largest non-accessibility text size, on a narrow width, must fit.
    @Test func `A full card fits the snippet height limit at the largest standard text size`() {
        let host = UIHostingController(rootView: view(fullCard()).environment(\.dynamicTypeSize, .xxxLarge))

        let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))

        #expect(size.height <= 400, "Card is \(size.height) pt tall")
    }

    /// Status is drawn in the app's adherence colors (and in words; see the model tests).
    @Test func `A late departure's status is drawn in the late color`() throws {
        let late = ThemeColors.shared.departureLate.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        let render = try HostedRender(view(fullCard()), size: CGSize(width: 360, height: 400))

        #expect(try render.boundingBox(of: late) != nil)
    }

    @Test func `Card intents read an empty id as no bookmark and reject garbage`() {
        let id = UUID()

        #expect(NextDeparturesCardKey(id.uuidString) == .bookmark(id))
        #expect(NextDeparturesCardKey("") == .noBookmark)
        #expect(NextDeparturesCardKey("not-a-uuid") == .invalid)
    }
}
