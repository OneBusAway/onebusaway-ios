//
//  AgenciesViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import SafariServices
import OBAKitCore

/// Loads and displays a list of agencies in the current region.
class AgenciesViewController: OperationController<DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>>, [AgencyWithCoverage]>, ListAdapterDataSource {

    override init(application: Application) {
        super.init(application: application)

        title = OBALoc("agencies_controller.title", value: "Agencies", comment: "Title of the Agencies controller")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    override func loadData() -> DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>>? {
        guard let apiService = application.restAPIService else { return nil }

        SVProgressHUD.show()

        let op = apiService.getAgenciesWithCoverage()
        op.complete { [weak self] result in
            SVProgressHUD.dismiss()
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
        collectionController.reload(animated: false)
    }

    // MARK: - IGListKit

    private lazy var collectionController = CollectionController(application: application, dataSource: self, style: .plain)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        guard let agencies = data else { return [] }

        let rows = agencies.sorted(by: {$0.agency.name < $1.agency.name}).map { agency -> TableRowData in
            TableRowData(title: agency.agency.name, accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let safari = SFSafariViewController(url: agency.agency.agencyURL)
                self.application.viewRouter.present(safari, from: self)
            }
        }

        return [TableSectionData(rows: rows)]
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }
}
