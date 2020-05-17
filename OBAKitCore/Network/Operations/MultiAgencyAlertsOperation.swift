//
//  MultiAgencyAlertsOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `[AgencyAlertsModelOperation]` model response to several API requests
/// to the `/api/gtfs_realtime/alerts-for-agency/{ID}.pb` endpoint.
///
/// This class accumulates responses to requests to individual agencies operating in the current region, and provides a flattened list
/// of all `AgencyAlert`s for the region.
public class MultiAgencyAlertsOperation: Operation, HasAgencyAlerts {
    public var agencyAlertsOperations = [AgencyAlertsOperation]()
    public private(set) var agencyAlerts = [AgencyAlert]()
    private let dispatchQueue = DispatchQueue(label: "org.onebusaway.multi_agency_alerts")

    override public func addDependency(_ op: Operation) {
        super.addDependency(op)

        dispatchQueue.sync {
            if let op = op as? AgencyAlertsOperation {
                agencyAlertsOperations.append(op)
            }
        }
    }

    override public func main() {
        super.main()
        agencyAlerts = agencyAlertsOperations.flatMap { $0.agencyAlerts }
        invokeCompletionHandler()
    }

    // MARK: - Completion Handler

    private var completionHandler: (([AgencyAlert]) -> Void)? {
        didSet {
            if isFinished {
                invokeCompletionHandler()
            }
        }
    }

    private func invokeCompletionHandler() {
        guard let handler = completionHandler else { return }

        DispatchQueue.main.async {
            handler(self.agencyAlerts)
        }

        completionHandler = nil
    }

    public func complete(completionHandler: @escaping (([AgencyAlert]) -> Void)) {
        self.completionHandler = completionHandler
    }
}

/// Describes a class that can return a list of `AgencyAlert`s.
protocol HasAgencyAlerts: NSObjectProtocol {
    var agencyAlerts: [AgencyAlert] { get }
}
