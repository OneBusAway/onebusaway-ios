//
//  ComplicationTests.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import XCTest
import ClockKit
@testable import OneBusAway_Watch

class ComplicationTests: XCTestCase {
    var complicationProvider: ComplicationProvider!
    
    override func setUp() {
        super.setUp()
        complicationProvider = ComplicationProvider()
    }
    
    override func tearDown() {
        complicationProvider = nil
        super.tearDown()
    }
    
    func testPlaceholder() {
        // Given
        let context = MockTimelineContext()
        
        // When
        let entry = complicationProvider.placeholder(in: context)
        
        // Then
        XCTAssertNotNil(entry)
        XCTAssertNotNil(entry.arrival)
    }
    
    func testGetSnapshot() {
        // Given
        let context = MockTimelineContext()
        let expectation = XCTestExpectation(description: "Get snapshot")
        
        // When
        complicationProvider.getSnapshot(in: context) { entry in
            // Then
            XCTAssertNotNil(entry)
            XCTAssertNotNil(entry.arrival)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetTimeline() {
        // Given
        let context = MockTimelineContext()
        let expectation = XCTestExpectation(description: "Get timeline")
        
        // When
        complicationProvider.getTimeline(in: context) { timeline in
            // Then
            XCTAssertNotNil(timeline)
            XCTAssertFalse(timeline.entries.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// Mock Timeline Context for testing
class MockTimelineContext: TimelineProviderContext {
    var family: CLKComplicationFamily = .modularSmall
    var device: CLKDevice = CLKDevice()
    var displayedComplication: CLKComplication? = nil
    var isFullColor: Bool = true
}

