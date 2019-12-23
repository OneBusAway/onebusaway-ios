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
    public let category: AnalyticsEvent
    public let label: String
    public let value: Any?
}

class AnalyticsMock: NSObject, Analytics {
    public private(set) var loggedEvents = [LoggedEvent]()
    public private(set) var reportedEvents = [ReportedEvent]()

    func logEvent(name: String, parameters: [String: Any]) {
        loggedEvents.append(LoggedEvent(name: name, parameters: parameters))
    }

    func reportEvent(category: AnalyticsEvent, label: String, value: Any?) {
        reportedEvents.append(ReportedEvent(category: category, label: label, value: value))
    }
}
