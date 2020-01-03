//
//  AnalyticsMock.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 7/9/19.
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
