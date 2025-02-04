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
    
    func reportStopViewed(name: String, id: String, stopDistance: String) {
        //
    }
    
    func reportSetRegion(_ name: String) {
        //
    }
    
    func setUserProperty(key: String, value: String?) {
        //
    }

    func updateServer(defaultDomainURL: URL, analyticsServerURL: URL?) {
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
