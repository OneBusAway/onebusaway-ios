//
//  AgencyAlertsStore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log

@objc public protocol AgencyAlertsDelegate: NSObjectProtocol {
    @objc optional func agencyAlertsUpdated()
    @objc optional func agencyAlertsStore(_ store: AgencyAlertsStore, displayError error: Error)
}

public class AgencyAlertsStore: NSObject, RegionsServiceDelegate {
    public var betterAPIService: RESTAPIService?
    public var obacoService: ObacoAPIService?

    private let userDefaults: UserDefaults

    public struct UserDefaultKeys {
        public static let displayRegionalTestAlerts = "displayRegionalTestAlerts"
        static let readAgencyAlertIDs = "readAgencyAlertIDs"
    }

    public init(userDefaults: UserDefaults, regionsService: RegionsService) {
        self.userDefaults = userDefaults
        self.userDefaults.register(defaults: [
            UserDefaultKeys.displayRegionalTestAlerts: false
        ])

        self.regionsService = regionsService

        super.init()

        self.regionsService.addDelegate(self)
    }

    deinit {
        cancelAllOperations()
    }

    // MARK: - Regions Service

    private let regionsService: RegionsService

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        cancelAllOperations()
        deleteAgencyAlerts()
        checkForUpdates()
    }

    // MARK: - Updates

    /// Cancels all pending data operations.
    private func cancelAllOperations() {
        queue.cancelAllOperations()
    }

    private var agencies = [AgencyWithCoverage]()

    public func update() async throws {
        guard let betterAPIService else { return }

        if agencies.isEmpty {
            agencies = try await betterAPIService.getAgenciesWithCoverage().list
        }

        // Get agency alerts from OBA and Obaco.
        let agencyAlerts = try await withThrowingTaskGroup(of: [AgencyAlert].self) { group -> [AgencyAlert] in
            group.addTask {
                try await self.fetchRegionalAlerts(service: betterAPIService)
            }

            group.addTask {
                try await self.fetchObacoAlerts()
            }

            var alerts: [AgencyAlert] = []
            for try await value in group {
                alerts.append(contentsOf: value)
            }

            return alerts
        }

        await storeAgencyAlerts(agencyAlerts)
    }

    /// Convenience wrapper for ``update()``. Errors are reported via ``AgencyAlertsDelegate``.
    public func checkForUpdates() {
        Task {
            do {
                try await update()
            } catch {
                await MainActor.run {
                    self.notifyDelegates(error: error)
                }
            }
        }
    }

    // MARK: - REST API
    private func fetchRegionalAlerts(service: RESTAPIService) async throws -> [AgencyAlert] {
        return try await service.getAlerts(agencies: agencies)
    }

    // MARK: - Obaco
    private func fetchObacoAlerts() async throws -> [AgencyAlert] {
        guard let obacoService else {
            return []
        }

        return try await obacoService.getAlerts(agencies: agencies)
    }

    // MARK: - High Severity Alerts

    /// Filters the contents of `recentHighSeverityAlerts` to just the items that are unread.
    public var recentUnreadHighSeverityAlerts: [AgencyAlert] {
        recentHighSeverityAlerts.filter { isAlertUnread($0) }
    }

    /// This property returns all `AgencyAlert`s from the last eight hours that have a
    /// GTFS-RT `SeverityLevel` of `WARNING` or `SEVERE`.
    public var recentHighSeverityAlerts: [AgencyAlert] {
        return agencyAlerts.filter { alert in
            guard
                alert.isHighSeverity,
                let startDate = alert.startDate,
                // Did this start less than 8 hours ago?
                abs(startDate.timeIntervalSinceNow) < 60 * 60 * 8
            else {
                return false
            }

            return true
        }
    }

    // MARK: - Read State

    private lazy var readAlertIDs: Set<String> = {
        let vals = userDefaults.array(forKey: UserDefaultKeys.readAgencyAlertIDs) as? [String]
        var set = Set(vals ?? [String]())
        return set
    }()

    public func markAlertRead(_ alert: AgencyAlert) {
        readAlertIDs.insert(alert.id)
        userDefaults.set(readAlertIDs.allObjects, forKey: UserDefaultKeys.readAgencyAlertIDs)
    }

    public func isAlertUnread(_ alert: AgencyAlert) -> Bool {
        !readAlertIDs.contains(alert.id)
    }

    // MARK: - Data Storage

    public var agencyAlerts: [AgencyAlert] {
        alerts.allObjects.sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
    }

    private var alerts: Set<AgencyAlert> = []

    @MainActor
    private func storeAgencyAlerts(_ agencyAlerts: [AgencyAlert]) {
        for alert in agencyAlerts {
            self.alerts.insert(alert)
        }

        self.notifyDelegatesAlertsUpdated()
    }

    /// Deletes all local data. Useful in preparation for changing the region.
    private func deleteAgencyAlerts() {
        queue.addOperation { [weak self] in
            guard let self = self else { return }
            self.userDefaults.set([], forKey: UserDefaultKeys.readAgencyAlertIDs)
            self.agencies.removeAll()
            self.readAlertIDs.removeAll()
            self.alerts.removeAll()
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
                d.agencyAlertsUpdated?()
            }
        }
    }

    private func notifyDelegates(error: Error) {
        let delegates = self.delegates.allObjects
        DispatchQueue.main.async {
            for d in delegates {
                d.agencyAlertsStore?(self, displayError: error)
            }
        }
    }
}
