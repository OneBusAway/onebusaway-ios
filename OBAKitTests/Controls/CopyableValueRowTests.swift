//
//  CopyableValueRowTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct CopyableValueRowTests {

    /// Verifies default initialization properties and localized confirmation message.
    @Test func testCopyableValueRowProperties() {
        let row = CopyableValueRow(title: "Stop ID", value: "1_75403")
        #expect(row.title == "Stop ID")
        #expect(row.value == "1_75403")
        #expect(row.accessibilityHint == nil)
        #expect(row.truncatesValue == false)

        let confirmation = CopyableValueRow.confirmation
        #expect(!confirmation.isEmpty)
        #expect(confirmation != "MISSING")
    }
}
