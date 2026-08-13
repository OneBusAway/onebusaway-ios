//
//  AlertPresenterTests.swift
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
final class AlertPresenterTests {
    
    var viewController: MockPresentingViewController!
    
    init() {
        viewController = MockPresentingViewController()
    }
    
    @Test @MainActor
    func `Show error with error`() async {
        let error = TestError.testError
        
        await AlertPresenter.show(error: error, presentingController: viewController)
        
        #expect(self.viewController.presentCallCount == 1)
        #expect(self.viewController.presentedAlert != nil)
        
        guard let alertController = self.viewController.presentedAlert else {
            Issue.record("Expected alert to be presented")
            return
        }
        
        #expect(alertController.title == Strings.error)
        #expect(alertController.message == error.localizedDescription)
        #expect(alertController.actions.count == 1)
        #expect(alertController.actions.first?.title == Strings.dismiss)
    }
    
    @Test @MainActor
    func `Show error with error message`() async {
        let errorMessage = "Test error message"
        
        await AlertPresenter.show(errorMessage: errorMessage, presentingController: viewController)
        
        #expect(self.viewController.presentCallCount == 1)
        #expect(self.viewController.presentedAlert != nil)
        
        guard let alertController = self.viewController.presentedAlert else {
            Issue.record("Expected alert to be presented")
            return
        }
        
        #expect(alertController.title == Strings.error)
        #expect(alertController.message == errorMessage)
        #expect(alertController.actions.count == 1)
        #expect(alertController.actions.first?.title == Strings.dismiss)
    }
    
    @Test @MainActor
    func `Show dismissable alert`() async {
        let title = "Test Title"
        let message = "Test Message"
        
        await AlertPresenter.showDismissableAlert(title: title, message: message, presentingController: viewController)
        
        #expect(self.viewController.presentCallCount == 1)
        #expect(self.viewController.presentedAlert != nil)
        
        guard let alertController = self.viewController.presentedAlert else {
            Issue.record("Expected alert to be presented")
            return
        }
        
        #expect(alertController.title == title)
        #expect(alertController.message == message)
        #expect(alertController.actions.count == 1)
        #expect(alertController.actions.first?.title == Strings.dismiss)
        #expect(alertController.preferredStyle == UIAlertController.Style.alert)
    }
    
    @Test @MainActor
    func `Show dismissable alert with nil title and message`() async {
        await AlertPresenter.showDismissableAlert(title: nil, message: nil, presentingController: viewController)
        
        #expect(self.viewController.presentCallCount == 1)
        #expect(self.viewController.presentedAlert != nil)
        
        guard let alertController = self.viewController.presentedAlert else {
            Issue.record("Expected alert to be presented")
            return
        }
        
        #expect(alertController.title == nil)
        #expect(alertController.message == nil)
        #expect(alertController.actions.count == 1)
        #expect(alertController.actions.first?.title == Strings.dismiss)
    }
}

// Helper error for testing
enum TestError: Error, LocalizedError {
    case testError
    
    var errorDescription: String? {
        switch self {
        case .testError:
            return "This is a test error"
        }
    }
}
