//
//  AgenciesViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import UIKit
import IGListKit
import SafariServices
import OBAKitCore

/// Loads and displays a list of agencies in the current region.
class AgenciesViewController: OperationController<AgenciesWithCoverageModelOperation, [AgencyWithCoverage]>, ListAdapterDataSource {

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

    override func loadData() -> AgenciesWithCoverageModelOperation? {
        guard let modelService = application.restAPIModelService else { return nil }

        SVProgressHUD.show()

        let op = modelService.getAgenciesWithCoverage()
        op.then { [weak self] in
            SVProgressHUD.dismiss()

            guard let self = self else { return }
            self.data = op.agenciesWithCoverage
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

        return [TableSectionData(title: nil, rows: rows)]
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }
}
