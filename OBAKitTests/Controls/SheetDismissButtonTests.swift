//
//  SheetDismissButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
struct SheetDismissButtonTests {

    @Test func testKindTitleMapping() {
        let closeButton = SheetDismissButton(.close) {}
        let cancelButton = SheetDismissButton(.cancel) {}
        let doneButton = SheetDismissButton(.done) {}

        #expect(closeButton.title == Strings.close)
        #expect(cancelButton.title == Strings.cancel)
        #expect(doneButton.title == Strings.done)
    }

    @available(iOS 26.0, *)
    @Test func testKindRoleMapping() {
        let closeButton = SheetDismissButton(.close) {}
        let cancelButton = SheetDismissButton(.cancel) {}
        let doneButton = SheetDismissButton(.done) {}

        #expect(closeButton.role == .close)
        #expect(cancelButton.role == .cancel)
        #expect(doneButton.role == .confirm)
    }
}
