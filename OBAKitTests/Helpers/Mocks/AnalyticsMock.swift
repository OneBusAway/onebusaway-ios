//
//  AnalyticsMock.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKit

struct ReportedEvent {
    public let pageURL: String
    public let label: String
    public let value: Any?
}

class AnalyticsMock: NSObject, Analytics {
    func reportSearchQuery(_ query: String) {
        //
    }
    
    public private(set) var stopViewedCount = 0
    public private(set) var lastReportedStopID: String?

    func reportStopViewed(name: String, id: String, stopDistance: String) {
        stopViewedCount += 1
        lastReportedStopID = id
    }
    
    func reportSetRegion(_ name: String) {
        //
    }
    
    func setUserProperty(key: String, value: String?) {
        //
    }

    func updateServer(region: Region) {
        //
    }

    private var isReportingEnabled = true

    func setReportingEnabled(_ enabled: Bool) {
        isReportingEnabled = enabled
    }

    func reportingEnabled() -> Bool {
        return isReportingEnabled
    }

    public private(set) var reportedEvents = [ReportedEvent]()

    func reportEvent(pageURL: String, label: String, value: Any?) {
        reportedEvents.append(ReportedEvent(pageURL: pageURL, label: label, value: value))
    }
}
