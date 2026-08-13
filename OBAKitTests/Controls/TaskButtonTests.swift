//
//  TaskButtonTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import SwiftUI
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class TaskButtonTests {
    
    @Test func `Action option all cases`() {
        let allCases = TaskButton<Text>.ActionOption.allCases
        
        #expect(allCases.count == 2)
        #expect(allCases.contains(.disableButton))
        #expect(allCases.contains(.showProgressView))
    }
    
    @Test func `Task button with text init`() {
        let testAction: () async -> Void = { }
        _ = TaskButton("Test Button", action: testAction)
    }
    
    @Test func `Task button with text custom action options`() {
        let testAction: () async -> Void = { }
        let customOptions: Set<TaskButton<Text>.ActionOption> = [.disableButton]
        let button = TaskButton("Test Button", actionOptions: customOptions, action: testAction)
        
        #expect(button.actionOptions == customOptions)
    }

    @Test func `Task button with image init`() {
        let testAction: () async -> Void = { }
        _ = TaskButton(systemImageName: "star", action: testAction)
    }
    
    @Test func `Task button with image custom action options`() {
        let testAction: () async -> Void = { }
        let customOptions: Set<TaskButton<Image>.ActionOption> = [.showProgressView]
        let button = TaskButton(systemImageName: "star", actionOptions: customOptions, action: testAction)
        
        #expect(button.actionOptions == customOptions)
    }
    
    @Test func `Task button generic init`() {
        let testAction: () async -> Void = { }
        let button = TaskButton(action: testAction) {
            Text("Custom Label")
        }
        
        #expect(button.actionOptions == Set(TaskButton<Text>.ActionOption.allCases))
    }
}
