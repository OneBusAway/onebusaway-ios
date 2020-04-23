//
//  AgencyAlertsOperation.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 4/30/20.
//

import Foundation

public class AgencyAlertsOperation: NetworkOperation, HasAgencyAlerts {
    private let agencies: [AgencyWithCoverage]
    public private(set) var agencyAlerts = [AgencyAlert]()

    public init(agencies: [AgencyWithCoverage], URL: URL) {
        self.agencies = agencies
        super.init(request: NetworkOperation.buildRequest(for: URL))
    }

    override func set(data: Data?, response: HTTPURLResponse?, error: Error?) {
        super.set(data: data, response: response, error: error)

        guard
            let data = data,
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

        agencyAlerts = qualifiedEntities.compactMap { (e: TransitRealtime_FeedEntity) -> AgencyAlert? in
            try? AgencyAlert(feedEntity: e, agencies: agencies)
        }
    }

    override func finish() {
        super.finish()
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
