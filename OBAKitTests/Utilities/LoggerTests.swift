//
//  LoggerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class LoggerTests {
    
    @Test func `Logger correctly writes and retrieves logs`() async throws {
        // Given
        let testMessage = "Test log message \(UUID().uuidString)"
        
        // When
        Logger.info(testMessage)
        
        // Then: Poll OSLogStore since it writes asynchronously
        var logsFound = false
        for _ in 0..<20 {
            let logs = Logger.combinedLogContent()
            if logs.contains(testMessage) {
                logsFound = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        #expect(logsFound == true, "Log message was not found in OSLogStore after polling")
    }
}
