//
//  MoreViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/27/19.
//

import UIKit
import AloeStackView
import SafariServices
import MessageUI

/// Provides access to OneBusAway Settings (Region configuration, etc.)
@objc(OBAMoreViewController) public class MoreViewController: UIViewController, AloeStackTableBuilder, MFMailComposeViewControllerDelegate {

    /// The OBA application object
    private let application: Application

    var theme: Theme { return application.theme }

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: application.theme.colors.groupedTableBackground
    )

    /// A helper object that crafts support emails or alerts when the user's email client isn't configured properly.
    private lazy var contactUsHelper = ContactUsHelper(application: application)

    /// Creates a Settings controller
    /// - Parameter application: The OBA application object
    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("more_controller.title", value: "More", comment: "Title of the More tab")
        tabBarItem.image = Icons.moreTabIcon

        let contactUs = NSLocalizedString("more_controller.contact_us", value: "Contact Us", comment: "A button to contact transit agency/developers.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: contactUs, style: .plain, target: self, action: #selector(showContactUsDialog))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.settings, style: .plain, target: self, action: #selector(showSettings))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        reloadTable()
    }

    private func reloadTable() {
        if application.userDataStore.debugMode {
            addDebug()
        }

        addHeader()
        addUpdatesAndAlerts()
        addMyLocationSection()
        addAbout()
    }

    // MARK: - Actions

    @objc func showSettings() {
        // TODO
    }

    // MARK: - Table Section Builders

    private lazy var moreHeaderController = MoreHeaderViewController(application: application)

    private func addHeader() {
        prepareChildController(moreHeaderController) {
            stackView.addRow(moreHeaderController.view, hideSeparator: true, insets: .zero)
        }
    }

    private func addUpdatesAndAlerts() {
        guard let region = application.currentRegion else { return }

        addTableHeaderToStack(headerText: NSLocalizedString("more_controller.updates_and_alerts.header", value: "Updates and Alerts", comment: "Updates and Alerts header text"))

        let fmtString = NSLocalizedString("more_controller.updates_and_alerts.row_fmt", value: "Alerts for %@", comment: "Alerts for {Region Name}")
        let text = String(format: fmtString, region.regionName)
        let row = DefaultTableRowView(title: text, accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(row, isLastRow: true) { _ in
            // TODO
        }
    }

    // MARK: - My Location Section

    private func addMyLocationSection() {
        addTableHeaderToStack(headerText: NSLocalizedString("more_controller.my_location.header", value: "My Location", comment: "'My Location' section header on the 'More' controller."))

        addRegionPickerRowToStackView()

        if let currentRegion = application.currentRegion, currentRegion.supportsMobileFarePayment {
            addPayMyFareRowToStackView()
        }

        addAgenciesRowToStackView()
    }

    private func addRegionPickerRowToStackView() {
        let regionRowTitle = NSLocalizedString("more_controller.my_location.region_row_title", value: "Region", comment: "Title of the row that lets the user choose their current region.")
        let currentRegionName = application.currentRegion?.regionName ?? ""
        let regionRow = ValueTableRowView(title: regionRowTitle, subtitle: currentRegionName, accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(regionRow) { [weak self] _ in
            guard let self = self else { return }

            let regionPicker = RegionPickerViewController(application: self.application)
            let nav = self.application.viewRouter.buildNavigation(controller: regionPicker)
            self.application.viewRouter.present(nav, from: self)
        }
    }

    private func addPayMyFareRowToStackView() {
        let rowTitle = NSLocalizedString("more_controller.my_location.pay_fare", value: "Pay My Fare", comment: "Title of the mobile fare payment row")
        let payMyFareRow = DefaultTableRowView(title: rowTitle, accessoryType: .none)
        addGroupedTableRowToStack(payMyFareRow) { [weak self] _ in
            guard let self = self else { return }
            self.logRowTapAnalyticsEvent(name: "Pay Fare")
            // todo: fare payment workflow.
        }
    }

    private func addAgenciesRowToStackView() {
        let rowTitle = NSLocalizedString("more_controller.my_location.agencies", value: "Agencies", comment: "Title of the Agencies row in the My Location section")
        let row = DefaultTableRowView(title: rowTitle, accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(row) { [weak self] _ in
            guard let self = self else { return }
            self.logRowTapAnalyticsEvent(name: "Show Agencies")
            let agencies = AgenciesViewController(application: self.application)
            self.application.viewRouter.navigate(to: agencies, from: self)
        }
    }

    // MARK: - Contact Us

    func presentEmailFeedbackForm(target: EmailTarget) {
        guard let composer = contactUsHelper.buildMailComposer(target: target) else {
            let alert = contactUsHelper.buildCantSendEmailAlert(target: target)
            present(alert, animated: true, completion: nil)
            return
        }

        composer.mailComposeDelegate = self
        present(composer, animated: true, completion: nil)
    }

    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)

        if let error = error {
            AlertPresenter.show(error: error, presentingController: self)
        }
    }

    @objc func showContactUsDialog() {
        // TODO
        let sheetTitle = NSLocalizedString("more_controller.contact_us_alert_title", value: "Contact Us", comment: "Contact Us alert title.")
        let sheet = UIAlertController(title: sheetTitle, message: nil, preferredStyle: .actionSheet)

        // Contact Developers
        let contactDevelopers = NSLocalizedString("more_controller.contact_developers", value: "Feature Request/Bug Report", comment: "Title of the action sheet option for contacting the developers of the app.")
        sheet.addAction(UIAlertAction(title: contactDevelopers, style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            self.presentEmailFeedbackForm(target: .appDevelopers)
        }))

        // Contact Transit Agency
        let contactTransit = NSLocalizedString("more_controller.contact_transit", value: "Vehicle/Schedule Problem", comment: "Title of the action sheet option for contacting a user's transit agency.")
        sheet.addAction(UIAlertAction(title: contactTransit, style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            self.presentEmailFeedbackForm(target: .transitAgency)
        }))

        sheet.addAction(UIAlertAction.cancelAction)

        present(sheet, animated: true, completion: nil)
    }

    // MARK: - About

    private func addAbout() {
        // Header
        addTableHeaderToStack(headerText: NSLocalizedString("more_controller.about_app", value: "About this App", comment: "Header for a section that shows the user information about this app."))

        // Credits
        let credits = DefaultTableRowView(title: NSLocalizedString("more_controller.credits_row_title", value: "Credits", comment: "Credits - like who should get credit for creating this."), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(credits) { _ in
            // TODO
        }

        // Privacy
        let privacy = DefaultTableRowView(title: NSLocalizedString("more_controller.privacy_row_title", value: "Privacy Policy", comment: "A link to the app's Privacy Policy"), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(privacy) { [weak self] _ in
            guard
                let self = self,
                let url = Bundle.main.privacyPolicyURL
            else { return }

            let safari = SFSafariViewController(url: url)
            safari.modalPresentationStyle = .overFullScreen
            self.application.viewRouter.present(safari, from: self)
        }

        // Weather
        let weather = DefaultTableRowView(title: NSLocalizedString("more_controller.weather_credits_row", value: "Weather forecasts powered by Dark Sky", comment: "Weather forecast attribution"), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(weather, isLastRow: true) { [weak self] _ in
            guard let self = self else { return }
            self.application.open(URL(string: "https://darksky.net/poweredby/")!, options: [:], completionHandler: nil)
        }
    }

    private func addDebug() {
//        - (OBATableSection*)debugTableSection {
//            OBATableSection *section = [[OBATableSection alloc] initWithTitle:NSLocalizedString(@"info_controller.debug_section_title", @"The table section title for the debugging tools.")];
//
//            OBATableRow *pushIDRow = [[OBATableRow alloc] initWithTitle:@"Push User ID" action:^(OBABaseRow *row) {
//                [UIPasteboard generalPasteboard].string = OBAPushManager.pushManager.pushNotificationUserID;
//                }];
//            pushIDRow.style = UITableViewCellStyleSubtitle;
//            pushIDRow.subtitle = OBAPushManager.pushManager.pushNotificationUserID;
//            [section addRow:pushIDRow];
//
//            OBATableRow *pushTokenRow = [[OBATableRow alloc] initWithTitle:@"Push Token" action:^(OBABaseRow *row) {
//                [UIPasteboard generalPasteboard].string = OBAPushManager.pushManager.pushNotificationToken;
//                }];
//            pushTokenRow.style = UITableViewCellStyleSubtitle;
//            pushTokenRow.subtitle = OBAPushManager.pushManager.pushNotificationToken;
//            [section addRow:pushTokenRow];
//
//            OBATableRow *row = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"info_controller.browse_user_defaults_row", @"Row title for the Browse User Defaults action") action:^(OBABaseRow *r2) {
//                [self logRowTapAnalyticsEvent:@"User Defaults Browser"];
//                UserDefaultsBrowserViewController *browser = [[UserDefaultsBrowserViewController alloc] init];
//                [self.navigationController pushViewController:browser animated:YES];
//                }];
//            row.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//            [section addRow:row];
//
//            row = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"info_controller.export_user_defaults_row", @"Row title for Export Defaults action") action:^(OBABaseRow *r2) {
//                [self logRowTapAnalyticsEvent:@"Export Defaults"];
//                NSData *archivedData = [[OBAApplication sharedApplication] exportUserDefaultsAsXML];
//                NSURL *URL = [FileHelpers urlToFileName:@"userdefaults.xml" inDirectory:NSDocumentDirectory];
//                [archivedData writeToURL:URL atomically:YES];
//
//                [self displayDocumentInteractionControllerForURL:URL];
//                }];
//            [section addRow:row];
//
//            return section;
//        }
    }

    // MARK: - Private Helpers

    private func logRowTapAnalyticsEvent(name: String) {
        application.analytics?.logEvent(name: "infoRowTapped", parameters: ["row": name])
    }
}
