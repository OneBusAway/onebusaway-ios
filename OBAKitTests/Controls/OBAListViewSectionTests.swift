//
//  OBAListViewSectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit

/// `NSDiffableDataSource` uses `Hashable` as identity. `hash(into:)` already
/// combines `id`; `==` used not to, so two agency-alert sections with the same
/// title and an empty row list compared equal while hashing differently —
/// undefined behavior, and the source of
/// "Failed to find index of item OBAListViewHeader".
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/421
@Suite(.serialized)
struct OBAListViewSectionTests {

    private func section(id: String, title: String?) -> OBAListViewSection {
        OBAListViewSection(id: id, title: title, contents: [OBAListRowView.DefaultViewModel]())
    }

    @Test func `Sections with the same title and contents but different ids are not equal`() {
        let ferriesA = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")
        let ferriesB = section(id: "agency_alerts_Washington State Ferries (other)", title: "Washington State Ferries")

        #expect(ferriesA != ferriesB)
    }

    @Test func `Equal sections include id and have matching hashes`() {
        let a = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")
        let b = section(id: "agency_alerts_Washington State Ferries", title: "Washington State Ferries")

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
