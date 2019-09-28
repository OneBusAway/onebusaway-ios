//
//  RegionalAlertsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

protocol HasAgencyAlerts: NSObjectProtocol {
    var agencyAlerts: [AgencyAlert] { get }
}

public class RegionalAlertsModelOperation: Operation, HasAgencyAlerts {
    public var agencyAlertsOperations = [AgencyAlertsModelOperation]()
    public private(set) var agencyAlerts = [AgencyAlert]()
    private let dispatchQueue = DispatchQueue(label: "org.onebusaway.regional-alerts")

    override public func addDependency(_ op: Operation) {
        super.addDependency(op)

        dispatchQueue.sync {
            if let op = op as? AgencyAlertsModelOperation {
                agencyAlertsOperations.append(op)
            }
        }
    }

    override public func main() {
        super.main()
        agencyAlerts = agencyAlertsOperations.flatMap { $0.agencyAlerts }
    }
}

public class AgencyAlertsModelOperation: Operation, HasAgencyAlerts, APIAssignee {
    public private(set) var agencyAlerts = [AgencyAlert]()

    public var apiOperation: Operation?
    let agencies: [AgencyWithCoverage]

    public init(agencies: [AgencyWithCoverage]) {
        self.agencies = agencies
    }

    override public func main() {
        super.main()

        guard
            let apiOperation = apiOperation as? NetworkOperation,
            let data = apiOperation.data,
            let message = try? TransitRealtime_FeedMessage(serializedData: data)
        else {
            return
        }

        let entities: [TransitRealtime_FeedEntity] = message.entity

        var qualifiedEntities = [TransitRealtime_FeedEntity]()

        for e in entities {
            let hasAlert = e.hasAlert
            let alert = e.alert
            let isAgencyWide = AgencyAlert.isAgencyWideAlert(alert: alert)

            if hasAlert && isAgencyWide {
                qualifiedEntities.append(e)
            }
        }

        let agencyAlerts = qualifiedEntities.compactMap { (e: TransitRealtime_FeedEntity) -> AgencyAlert? in
            do {
                return try AgencyAlert(feedEntity: e, agencies: agencies)
            } catch {
                return nil
            }
        }

        self.agencyAlerts = agencyAlerts
    }
}
