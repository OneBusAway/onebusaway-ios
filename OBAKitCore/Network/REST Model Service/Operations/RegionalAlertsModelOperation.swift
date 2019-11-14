//
//  RegionalAlertsModelOperation.swift
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

/// Creates a `[AgencyAlert]` GTFS-RT model response to an API request to
/// `/api/gtfs_realtime/alerts-for-agency/{ID}.pb`.
///
/// - Note: Normally you will not interact directly with this class, but use `RegionalAlertsModelOperation` instead.
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

/// Describes a class that can return a list of `AgencyAlert`s.
protocol HasAgencyAlerts: NSObjectProtocol {
    var agencyAlerts: [AgencyAlert] { get }
}
