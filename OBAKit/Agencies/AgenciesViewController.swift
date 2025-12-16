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
                    onSelectAction: { [weak self] _ in
                        self?.showAgencyOptions(agency)
                    })
            }

        return [OBAListViewSection(id: "agencies", title: nil, contents: rows)]
    }

    func showAgencyOptions(_ agency: AgencyWithCoverage) {
        let alert = UIAlertController(title: agency.agency.name, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(
            title: OBALoc("agencies_controller.open_website", value: "Open Website", comment: "Action to open agency website"),
            style: .default
        ) { [weak self] _ in
            self?.openAgencyWebsite(agency)
        })

        if !agency.agency.phone.isEmpty {
            alert.addAction(UIAlertAction(
                title: OBALoc("agencies_controller.call_agency", value: "Call Agency", comment: "Action to call agency"),
                style: .default
            ) { [weak self] _ in
                self?.callAgency(agency.agency)
            })
        }

        alert.addAction(UIAlertAction.cancelAction)
        application.viewRouter.present(
            alert,
            from: self,
            isPopover: traitCollection.userInterfaceIdiom == .pad,
            popoverBarButtonItem: nil
        )
    }

    func openAgencyWebsite(_ agency: AgencyWithCoverage) {
        let safari = SFSafariViewController(url: agency.agency.agencyURL)
        self.application.viewRouter.present(safari, from: self)
    }

    func callAgency(_ agency: Agency) {
        guard let phoneURL = agency.callURL else {
            showAlert(
                title: OBALoc("agencies_controller.error_title", value: "Error", comment: "Error dialog title"),
                message: OBALoc("agencies_controller.invalid_phone", value: "Invalid phone number.", comment: "Error message for invalid phone")
            )
            return
        }
        application.open(phoneURL, options: [:], completionHandler: nil)
    }

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
