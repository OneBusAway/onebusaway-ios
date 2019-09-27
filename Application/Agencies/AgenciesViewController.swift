//
//  AgenciesViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/2/19.
//

import UIKit
import AloeStackView
import SafariServices
import SVProgressHUD
import OBAKitCore

class AgenciesViewController: OperationController<AgenciesWithCoverageModelOperation, [AgencyWithCoverage]>, AloeStackTableBuilder {

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.systemBackground
    )

    override init(application: Application) {
        super.init(application: application)

        title = NSLocalizedString("agencies_controller.title", value: "Agencies", comment: "Title of the Agencies controller")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)
    }

    override func loadData() -> AgenciesWithCoverageModelOperation? {
        guard let modelService = application.restAPIModelService else { return nil }

        SVProgressHUD.show()

        let op = modelService.getAgenciesWithCoverage()
        op.then { [weak self] in
            guard let self = self else {
                SVProgressHUD.dismiss()
                return
            }
            self.data = op.agenciesWithCoverage
            SVProgressHUD.dismiss()
        }

        return op
    }

    override func updateUI() {
        guard let agencies = data else {
            return
        }

        for agency in agencies {
            let row = DefaultTableRowView(title: agency.agency.name, accessoryType: .disclosureIndicator)
            addGroupedTableRowToStack(row) { [weak self] _ in
                guard let self = self else { return }

                let safari = SFSafariViewController(url: agency.agency.agencyURL)
                self.application.viewRouter.present(safari, from: self)
            }
        }
    }
}
