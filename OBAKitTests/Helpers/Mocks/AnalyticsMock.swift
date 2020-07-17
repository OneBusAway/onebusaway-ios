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

struct LoggedEvent {
    public let name: String
    public let parameters: [String: Any]
}

struct ReportedEvent {
    public let event: AnalyticsEvent
    public let label: String
    public let value: Any?
}

class AnalyticsMock: NSObject, Analytics {

    private var isReportingEnabled = true

    func setReportingEnabled(_ enabled: Bool) {
        isReportingEnabled = enabled
    }

    func reportingEnabled() -> Bool {
        return isReportingEnabled
    }

    public private(set) var loggedEvents = [LoggedEvent]()
    public private(set) var reportedEvents = [ReportedEvent]()

    func logEvent(name: String, parameters: [String: Any]) {
        loggedEvents.append(LoggedEvent(name: name, parameters: parameters))
    }

    func reportEvent(_ event: AnalyticsEvent, label: String, value: Any?) {
        reportedEvents.append(ReportedEvent(event: event, label: label, value: value))
    }
}
