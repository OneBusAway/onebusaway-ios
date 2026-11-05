//
//  GhostBusReportViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class GhostBusReportViewTests {

    @Test func testGhostBusReportConstants() {
        #expect(GhostBusReportView.waitChoices == [5, 10, 15, 20, 30])
        #expect(GhostBusReportView.commentMaxLength == 1_000)
    }
}
