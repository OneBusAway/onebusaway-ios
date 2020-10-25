//
//  AgencyAlertsStore+ListView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/11/20.
//

import OBAKitCore

extension AgencyAlertsStore {
    /// Outputs the alerts in this store into a sorted `[OBAListViewSection]` for use with `OBAListView`
    ///
    /// - Parameters:
    ///   - onSelectAction: The optional closure to perform when the user selects the alert in `OBAListView`.
    /// - Returns: An array of `[OBAListViewSection]` grouped by Agency name. The sections provided will have a `agency_alert` prefix for its section ID.
    func listViewSections(onSelectAction: OBAListViewAction<AgencyAlert.ListViewModel>? = nil) -> [OBAListViewSection] {
        let groupedAlerts = Dictionary(grouping: agencyAlerts, by: { $0.agency?.agency.name ?? "" })
        return groupedAlerts.map { group -> OBAListViewSection in
            let viewModels = group.value.map { alert -> AgencyAlert.ListViewModel in
                var viewModel = alert.listViewModel
                viewModel.onSelectAction = onSelectAction
                return viewModel
            }

            let alerts = Set(viewModels).allObjects.sorted(by: \.title) // remove duplicates
            return OBAListViewSection(id: "agency_alerts_\(group.key)", title: group.key, contents: alerts)
        }.sorted(by: \.id)
    }
}
