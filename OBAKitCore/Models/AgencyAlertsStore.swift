//
//  AgencyAlertsStore.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/15/19.
//

import Foundation

@objc public protocol AgencyAlertsDelegate: NSObjectProtocol {
    func agencyAlertsUpdated()
}

public class AgencyAlertsStore: NSObject {
    public var restModelService: RESTAPIModelService?
    public var obacoModelService: ObacoModelService?

    private let userDefaults: UserDefaults

    public struct UserDefaultKeys {
        public static let displayRegionalTestAlerts = "displayRegionalTestAlerts"
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.userDefaults.register(defaults: [
            UserDefaultKeys.displayRegionalTestAlerts: false
        ])
    }

    deinit {
        agenciesOperation?.cancel()
        regionalAlertsOperation?.cancel()
        obacoOperation?.cancel()
        queue.cancelAllOperations()
    }

    // MARK: - Updates

    private var agenciesOperation: AgenciesWithCoverageModelOperation?

    private var agencies = [AgencyWithCoverage]()

    public func checkForUpdates() {
        guard let restModelService = restModelService else { return }

        // Step 1: download a list of agencies, if needed.
        if agencies.count == 0 {
            let agenciesOp = restModelService.getAgenciesWithCoverage()
            agenciesOperation = agenciesOp
            agenciesOp.then { [weak self] in
                guard let self = self else { return }
                self.agencies = agenciesOp.agenciesWithCoverage

                self.fetchRegionalAlerts()
                self.fetchObacoAlerts()
            }
        }
        else {
            fetchRegionalAlerts()
            fetchObacoAlerts()
        }
    }

    // MARK: - REST API

    private var regionalAlertsOperation: RegionalAlertsModelOperation?

    private func fetchRegionalAlerts() {
        guard let restModelService = restModelService else { return }

        let op = restModelService.getRegionalAlerts(agencies: agencies)
        regionalAlertsOperation = op

        op.then { [weak self] in
            guard let self = self else { return }
            self.storeAgencyAlerts(op.agencyAlerts)
        }
    }

    // MARK: - Obaco

    private var obacoOperation: AgencyAlertsModelOperation?

    private func fetchObacoAlerts() {
        guard let obacoModelService = obacoModelService else { return }

        let op = obacoModelService.getAlerts(agencies: agencies)
        obacoOperation = op

        op.then { [weak self] in
            guard let self = self else { return }
            self.storeAgencyAlerts(op.agencyAlerts)
        }
    }

    // MARK: - Data Storage

    public var agencyAlerts: [AgencyAlert] {
        alerts.allObjects.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    /// This property returns all `AgencyAlert`s from the last eight hours that
    /// have a GTFS-RT `SeverityLevel` of `WARNING` or `SEVERE`.
    public var recentHighSeverityAlerts: [AgencyAlert] {
        guard let first = agencyAlerts.first else {
            return []
        }

        return [first]
    }

    private var alerts = Set<AgencyAlert>() {
        didSet {
            notifyDelegatesAlertsUpdated()
        }
    }

    private func storeAgencyAlerts(_ agencyAlerts: [AgencyAlert]) {
        queue.addOperation { [weak self] in
            guard let self = self else { return }

            for alert in agencyAlerts {
                self.alerts.insert(alert)
            }
        }
    }

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: - Delegates

    private let delegates = NSHashTable<AgencyAlertsDelegate>.weakObjects()

    public func addDelegate(_ delegate: AgencyAlertsDelegate) {
        delegates.add(delegate)
    }

    public func removeDelegate(_ delegate: AgencyAlertsDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesAlertsUpdated() {
        let delegates = self.delegates.allObjects
        DispatchQueue.main.async {
            for d in delegates {
                d.agencyAlertsUpdated()
            }
        }
    }
}
