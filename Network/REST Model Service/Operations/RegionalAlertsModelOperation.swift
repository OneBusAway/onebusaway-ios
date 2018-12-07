//
//  RegionalAlertsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/6/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RegionalAlertsModelOperation: Operation {
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
        agencyAlerts = agencyAlertsOperations.flatMap { $0.gtfsAlerts }
    }
}

public class AgencyAlertsModelOperation: Operation {
    public private(set) var gtfsAlerts = [AgencyAlert]()

    public var apiOperation: NetworkOperation?
    let agency: AgencyWithCoverage

    public init(agency: AgencyWithCoverage) {
        self.agency = agency
    }

    override public func main() {
        super.main()

        guard
            let apiOperation = apiOperation,
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
                let alert = try AgencyAlert(feedEntity: e, agency: agency)
                return alert
            } catch {
                return nil
            }
        }

        gtfsAlerts = agencyAlerts
    }
}
