//
//  AgencyAlertsOperation.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class AgencyAlertsOperation: NetworkOperation, HasAgencyAlerts {
    private let agencies: [AgencyWithCoverage]
    public private(set) var agencyAlerts = [AgencyAlert]()

    public init(agencies: [AgencyWithCoverage], URL: URL, dataLoader: URLDataLoader) {
        self.agencies = agencies
        super.init(request: NetworkOperation.buildRequest(for: URL), dataLoader: dataLoader)
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
            do {
                return try AgencyAlert(feedEntity: e, agencies: agencies)
            } catch {
                return nil
            }
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
