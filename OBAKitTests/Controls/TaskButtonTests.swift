//
//  TaskButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
import SwiftUI
@testable import OBAKit

@available(iOS 14.0, *)
class TaskButtonTests: XCTestCase {
    
    func test_ActionOption_allCases() {
        let allCases = TaskButton<Text>.ActionOption.allCases
        
        expect(allCases.count) == 2
        expect(allCases).to(contain(.disableButton))
        expect(allCases).to(contain(.showProgressView))
    }
    
    func test_TaskButton_withText_init() {
        let testAction: () async -> Void = { }
        let button = TaskButton("Test Button", action: testAction)
        
        // Test that the button can be created without crashing
        expect(button).toNot(beNil())
    }
    
    func test_TaskButton_withText_customActionOptions() {
        let testAction: () async -> Void = { }
        let customOptions: Set<TaskButton<Text>.ActionOption> = [.disableButton]
        let button = TaskButton("Test Button", actionOptions: customOptions, action: testAction)
        
        expect(button).toNot(beNil())
        expect(button.actionOptions) == customOptions
    }
    
    func test_TaskButton_withImage_init() {
        let testAction: () async -> Void = { }
        let button = TaskButton(systemImageName: "star", action: testAction)
        
        expect(button).toNot(beNil())
    }
    
    func test_TaskButton_withImage_customActionOptions() {
        let testAction: () async -> Void = { }
        let customOptions: Set<TaskButton<Image>.ActionOption> = [.showProgressView]
        let button = TaskButton(systemImageName: "star", actionOptions: customOptions, action: testAction)
        
        expect(button).toNot(beNil())
        expect(button.actionOptions) == customOptions
    }
    
    func test_TaskButton_genericInit() {
        let testAction: () async -> Void = { }
        let button = TaskButton(action: testAction) {
            Text("Custom Label")
        }
        
        expect(button).toNot(beNil())
        expect(button.actionOptions) == Set(TaskButton<Text>.ActionOption.allCases)
    }
}
