//
//  OBAListViewActionExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class OBAListViewActionExtendedTests {

    private struct TestListItem: OBAListViewItem {
        var id: String = "test_item_1"
        var configuration: OBAListViewItemConfiguration = .custom(contentConfiguration: UIListContentConfiguration.cell())
    }

    // MARK: - Normal Style Mapping

    @Test func `Contextual action with normal style maps to normal UIContextualAction style`() {
        var action = OBAListViewContextualAction<TestListItem>()
        action.title = "Edit"
        action.style = .normal
        action.backgroundColor = .systemBlue

        let contextualAction = action.contextualAction

        #expect(contextualAction.style == .normal)
        #expect(contextualAction.title == "Edit")
        #expect(contextualAction.backgroundColor == .systemBlue)
    }

    // MARK: - Destructive Style Mapping

    @Test func `Contextual action with destructive style maps to destructive UIContextualAction style`() {
        var action = OBAListViewContextualAction<TestListItem>()
        action.title = "Delete"
        action.style = .destructive
        action.backgroundColor = .systemRed

        let contextualAction = action.contextualAction

        #expect(contextualAction.style == .destructive)
        #expect(contextualAction.title == "Delete")
    }

    // MARK: - Image Attachment

    @Test func `Contextual action preserves image property`() {
        var action = OBAListViewContextualAction<TestListItem>()
        let image = UIImage(systemName: "trash")
        action.image = image

        let contextualAction = action.contextualAction

        #expect(contextualAction.image == image)
    }
}
