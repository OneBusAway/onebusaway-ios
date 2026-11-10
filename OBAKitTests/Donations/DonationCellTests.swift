//
//  DonationCellTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// The donation card's three buttons each reach their own handler on the item the
/// cell was given.
@MainActor
@Suite(.serialized)
struct DonationCellTests {

    /// The handlers called, in order.
    private final class Calls {
        var names: [String] = []
    }

    private func cell(recordingInto calls: Calls) -> DonationCell {
        let item = DonationListItem(
            onSelectAction: { _ in calls.names.append("donate") },
            onLearnMoreAction: { _ in calls.names.append("learnMore") },
            onCloseAction: { _ in calls.names.append("close") }
        )
        let cell = DonationCell(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        cell.apply(DonationContentConfiguration(item))
        return cell
    }

    @Test func `The close button calls only the close handler`() {
        let calls = Calls()

        cell(recordingInto: calls).closeButton.sendActions(for: .touchUpInside)

        #expect(calls.names == ["close"])
    }

    @Test func `The Learn More button calls only the learn-more handler`() {
        let calls = Calls()

        cell(recordingInto: calls).learnMoreButton.sendActions(for: .primaryActionTriggered)

        #expect(calls.names == ["learnMore"])
    }

    @Test func `The Donate Now button calls only the donate handler`() {
        let calls = Calls()

        cell(recordingInto: calls).donateButton.sendActions(for: .touchUpInside)

        #expect(calls.names == ["donate"])
    }

    /// Cells are reused, so a button must reach the item the cell shows now.
    @Test func `A reused cell's buttons reach the item it was given last`() {
        let first = Calls()
        let second = Calls()
        let cell = cell(recordingInto: first)
        cell.apply(DonationContentConfiguration(DonationListItem(
            onSelectAction: { _ in second.names.append("donate") },
            onLearnMoreAction: nil,
            onCloseAction: { _ in second.names.append("close") }
        )))

        cell.donateButton.sendActions(for: .touchUpInside)
        cell.closeButton.sendActions(for: .touchUpInside)

        #expect(first.names.isEmpty)
        #expect(second.names == ["donate", "close"])
    }
}
