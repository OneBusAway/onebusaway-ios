//
//  ToastManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit

@Suite(.serialized)
@MainActor
final class ToastManagerTests {

    @Test func `Show success toast sets properties correctly`() {
        let manager = ToastManager()
        #expect(manager.isShowing == false)
        #expect(manager.toast == nil)
        
        manager.showSuccess("Success message", duration: 5.0)
        
        #expect(manager.isShowing == true)
        #expect(manager.toast?.message == "Success message")
        #expect(manager.toast?.type == .success)
        #expect(manager.toast?.duration == 5.0)
    }

    @Test func `Show error toast sets properties correctly`() {
        let manager = ToastManager()
        #expect(manager.isShowing == false)
        #expect(manager.toast == nil)
        
        manager.showError("Error message", duration: 2.0)
        
        #expect(manager.isShowing == true)
        #expect(manager.toast?.message == "Error message")
        #expect(manager.toast?.type == .error)
        #expect(manager.toast?.duration == 2.0)
    }

        @Test func `Dismiss toast clears visibility immediately and cleans up toast after delay`() async throws {
        let manager = ToastManager()
        manager.showSuccess("Dismiss me")
        #expect(manager.isShowing == true)
        
        manager.dismiss()
        
        // Visibility is cleared immediately
        #expect(manager.isShowing == false)
        #expect(manager.toast != nil)
        
        // Payload is cleaned up after a 0.3s delay (wait 0.4s to be safe)
        try await Task.sleep(nanoseconds: 400_000_000)
        
        #expect(manager.toast == nil)
    }
}

