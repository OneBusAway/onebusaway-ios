//
//  RESTAPIService+GetAgencyAlerts.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/29/22.
//

extension RESTAPIService {
    // MARK: - Regional Alerts
    public nonisolated func getAlerts(agencies: [AgencyWithCoverage]) async -> [AgencyAlert] {
        return await withTaskGroup(of: [AgencyAlert].self) { group -> [AgencyAlert] in
            for agency in agencies {
                group.addTask {
                    return await self.getAlerts(agency: agency)
                }
            }

            var alerts: [AgencyAlert] = []
            for await result in group {
                alerts.append(contentsOf: result)
            }
            return alerts
        }
    }

    public nonisolated func getAlerts(agency: AgencyWithCoverage) async -> [AgencyAlert] {
        let url = urlBuilder.getRESTRegionalAlerts(agencyID: agency.agencyID)

        do {
            let (data, _) = try await self.getData(for: url)
            let message = try TransitRealtime_FeedMessage(serializedBytes: data)
            return message.entity
                .filter(isQualifiedAlert)
                .compactMap {
                    // TODO: Don't swallow error
                    try? AgencyAlert(feedEntity: $0, agencies: [agency])
                }
        } catch {
            logger.error("getAlerts() failed for \(agency.agency.name, privacy: .public): \(error, privacy: .public)")
            return []
        }
    }

    private nonisolated func isQualifiedAlert(_ entity: TransitRealtime_FeedEntity) -> Bool {
        return entity.hasAlert && AgencyAlert.isAgencyWideAlert(alert: entity.alert)
    }
}
