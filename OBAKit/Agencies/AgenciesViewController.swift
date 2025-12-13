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
import MessageUI
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

    // MARK: - Agency Options
    func showAgencyOptions(_ agency: AgencyWithCoverage) {
        // DEBUG: Print the phone number
        print("Agency: \(agency.agency.name), Phone: \(agency.agency.phone)")
        
        let alert = UIAlertController(title: agency.agency.name, message: nil, preferredStyle: .actionSheet)

        // Open Website
        alert.addAction(UIAlertAction(title: "Open Website", style: .default) { [weak self] _ in
            self?.onSelectAgency(agency)
        })

        // Call Agency (always show, error if no phone)
        alert.addAction(UIAlertAction(title: "📞 Call Agency", style: .default) { [weak self] _ in
            self?.callAgency(agency.agency)
        })

        // Text Agency (always show, error if no phone)
        alert.addAction(UIAlertAction(title: "💬 Text Agency", style: .default) { [weak self] _ in
            self?.textAgency(agency.agency)
        })

        alert.addAction(UIAlertAction.cancelAction)
        application.viewRouter.present(
            alert,
            from: self,
            isPopover: traitCollection.userInterfaceIdiom == .pad,
            popoverBarButtonItem: nil
        )
    }

    func onSelectAgency(_ agency: AgencyWithCoverage) {
        let safari = SFSafariViewController(url: agency.agency.agencyURL)
        self.application.viewRouter.present(safari, from: self)
    }

    // MARK: - Agency Contact Methods
    func callAgency(_ agency: Agency) {
        let phoneNumber = agency.phone.trimmingCharacters(in: .whitespaces)
        
        // DEBUG: Print call number
        print("DEBUG - Calling agency: \(agency.name), Phone: \(phoneNumber)")
        
        guard !phoneNumber.isEmpty else {
            showAlert(title: "No Phone Number", message: "This agency does not have a phone number available.")
            return
        }
        let cleanNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        // DEBUG: Print cleaned number
        print("DEBUG - Cleaned phone number for call: \(cleanNumber)")
        
        guard let url = URL(string: "tel://\(cleanNumber)") else {
            showAlert(title: "Error", message: "Invalid phone number format.")
            return
        }
        application.open(url, options: [:], completionHandler: nil)
    }

    func textAgency(_ agency: Agency) {
        let phoneNumber = agency.phone.trimmingCharacters(in: .whitespaces)
        
        // DEBUG: Print SMS number
        print("DEBUG - Texting agency: \(agency.name), Phone: \(phoneNumber)")
        
        guard !phoneNumber.isEmpty else {
            showAlert(title: "No Phone Number", message: "This agency does not have a phone number available for SMS.")
            return
        }
        let cleanNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        // DEBUG: Print cleaned number for SMS
        print("DEBUG - Cleaned phone number for SMS: \(cleanNumber)")
        
        // Check if device can send SMS
        guard MFMessageComposeViewController.canSendText() else {
            showAlert(title: "Cannot Send SMS", message: "This device cannot send SMS messages.")
            return
        }
        
        let composer = MFMessageComposeViewController()
        composer.recipients = [cleanNumber]
        composer.messageComposeDelegate = self
        present(composer, animated: true)
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - MFMessageComposeViewControllerDelegate
extension AgenciesViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
