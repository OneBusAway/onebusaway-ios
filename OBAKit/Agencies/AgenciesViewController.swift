//
//  AgenciesViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SafariServices
import OBAKitCore

/// Loads and displays a list of agencies in the current region.
class AgenciesViewController: TaskController<[AgencyWithCoverage]>, OBAListViewDataSource {
    let listView = OBAListView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        title = OBALoc("agencies_controller.title", value: "Agencies", comment: "Title of the Agencies controller")
    }

    override func loadData() async throws -> [AgencyWithCoverage] {
        guard let apiService = application.apiService else {
            throw UnstructuredError("No API Service")
        }

        ProgressHUD.show()
        defer {
            Task { @MainActor in
                ProgressHUD.dismiss()
            }
        }

        return try await apiService.getAgenciesWithCoverage().list
    }

    @MainActor
    override func updateUI() {
        listView.applyData()
    }

    // MARK: - OBAListKit
    func items(for listView: OBAListView) -> [OBAListViewSection] {
        guard let agencies = data else { return [] }

        let rows = agencies
            .sorted(by: { $0.agency.name < $1.agency.name })
            .map { agency -> OBAListRowView.DefaultViewModel in
                OBAListRowView.DefaultViewModel(
                    title: agency.agency.name,
                    accessoryType: .disclosureIndicator,
                    onSelectAction: { _ in
                        self.onSelectAgency(agency)
                    })
            }

        return [OBAListViewSection(id: "agencies", title: nil, contents: rows)]
    }

    func onSelectAgency(_ agency: AgencyWithCoverage) {
        let safari = SFSafariViewController(url: agency.agency.agencyURL)
        self.application.viewRouter.present(safari, from: self)
    }
}
