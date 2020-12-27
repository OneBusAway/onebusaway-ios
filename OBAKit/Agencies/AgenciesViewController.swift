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
class AgenciesViewController: OperationController<DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>>, [AgencyWithCoverage]>, OBAListViewDataSource {
    let listView = OBAListView()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        title = OBALoc("agencies_controller.title", value: "Agencies", comment: "Title of the Agencies controller")
    }

    override func loadData() -> DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>>? {
        guard let apiService = application.restAPIService else { return nil }

        ProgressHUD.show()

        let op = apiService.getAgenciesWithCoverage()
        op.complete { [weak self] result in
            ProgressHUD.dismiss()
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                self.data = response.list
            }
        }

        return op
    }

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
