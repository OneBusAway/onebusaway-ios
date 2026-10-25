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

    @Test func testKindAllCasesInitialization() {
        let closeKind = SheetDismissButton.Kind.close
        let cancelKind = SheetDismissButton.Kind.cancel
        let doneKind = SheetDismissButton.Kind.done

        #expect(closeKind != cancelKind)
        #expect(cancelKind != doneKind)
        #expect(closeKind != doneKind)
    }

    @Test func testDismissButtonActionCallback() {
        var actionFired = false
        let button = SheetDismissButton(.close) {
            actionFired = true
        }

        #expect(button.kind == .close)
        #expect(actionFired == false)

        button.action()
        #expect(actionFired == true)
    }

    @Test func testDismissButtonKindsStoreExpectedKinds() {
        var cancelFired = false
        let cancelButton = SheetDismissButton(.cancel) {
            cancelFired = true
        }
        #expect(cancelButton.kind == .cancel)
        cancelButton.action()
        #expect(cancelFired == true)

        var doneFired = false
        let doneButton = SheetDismissButton(.done) {
            doneFired = true
        }
        #expect(doneButton.kind == .done)
        doneButton.action()
        #expect(doneFired == true)
    }

    @Test func testDismissButtonViewBodyEvaluation() {
        let button = SheetDismissButton(.done) {}
        let host = UIHostingController(rootView: button)
        _ = host.view
        #expect(host.view != nil)
    }
}
