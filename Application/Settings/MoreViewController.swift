//
//  MoreViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/27/19.
//

import UIKit
import AloeStackView
import SafariServices

/// Provides access to OneBusAway Settings (Region configuration, etc.)
@objc(OBAMoreViewController) public class MoreViewController: UIViewController, AloeStackTableBuilder {

    /// The OBA application object
    private let application: Application

    var theme: Theme { return application.theme }

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: application.theme.colors.groupedTableBackground
    )

    /// Creates a Settings controller
    /// - Parameter application: The OBA application object
    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = NSLocalizedString("more_controller.title", value: "More", comment: "Title of the More tab")
        tabBarItem.image = Icons.moreTabIcon

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
        addLocationSettings()
        addContactUs()
        addAbout()
    }

    // MARK: - Actions

    @objc func showSettings() {
        // TODO
    }

    // MARK: - Table Section Builders

    private func addHeader() {
        // TODO
    }

    private func addUpdatesAndAlerts() {
        guard let region = application.currentRegion else { return }

        addTableHeaderToStack(headerText: NSLocalizedString("more_controller.updates_and_alerts.header", value: "Updates and Alerts", comment: "Updates and Alerts header text"))

        let fmtString = NSLocalizedString("more_controller.updates_and_alerts.row_fmt", value: "Alerts for %@", comment: "Alerts for {Region Name}")
        let text = String(format: fmtString, region.regionName)
        let row = DefaultTableRowView(title: text, accessoryType: .disclosureIndicator)
        addTableRowToStack(row, isLastRow: true)
        stackView.setTapHandler(forRow: row) { _ in
            // TODO
        }
    }

    private func addLocationSettings() {
//        - (OBATableSection*)settingsTableSection {
//            NSMutableArray *rows = [[NSMutableArray alloc] init];
//
//            OBATableRow *region = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"msg_region", @"") action:^(OBABaseRow *r2) {
//            [self logRowTapAnalyticsEvent:@"Region List"];
//            [self.navigationController pushViewController:[[OBARegionListViewController alloc] initWithApplication:OBAApplication.sharedApplication] animated:YES];
//            }];
//            region.style = UITableViewCellStyleValue1;
//            region.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//            region.subtitle = self.modelDAO.currentRegion.regionName;
//            [rows addObject:region];
//
//            if (self.modelDAO.currentRegion.supportsMobileFarePayment) {
//                OBATableRow *payFare = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"msg_pay_fare", @"Pay My Fare table row") action:^(OBABaseRow *row) {
//                    [self logRowTapAnalyticsEvent:@"Pay Fare"];
//                    [self.farePayments beginFarePaymentWorkflow];
//                    }];
//                [rows addObject:payFare];
//            }
//
//            OBATableRow *agencies = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"msg_agencies", @"Info Page Agencies Row Title") action:^(OBABaseRow *r2) {
//                [self logRowTapAnalyticsEvent:@"Show Agencies"];
//                [self openAgencies];
//                }];
//            agencies.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//            [rows addObject:agencies];
//
//            return [OBATableSection tableSectionWithTitle:NSLocalizedString(@"msg_your_location", @"Settings section title on info page") rows:rows];
//        }

    }

    private func addContactUs() {
        
//        - (OBATableSection*)contactTableSection {
//            NSMutableArray *rows = [[NSMutableArray alloc] init];
//
//            OBATableRow *contactTransitAgency = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"msg_data_schedule_issues", @"Info Page Contact Us Row Title") action:^(OBABaseRow *r2) {
//            [self logRowTapAnalyticsEvent:@"Contact Transit Agency"];
//            [self contactTransitAgency];
//            }];
//            contactTransitAgency.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//            [rows addObject:contactTransitAgency];
//
//            OBATableRow *contactAppDevelopers = [[OBATableRow alloc] initWithTitle:NSLocalizedString(@"info_controller.contact_app_developers_row_title", @"'Contact app developers about a bug' row") action:^(OBABaseRow *r2) {
//            [self logRowTapAnalyticsEvent:@"Contact Developers"];
//            [self contactAppDevelopers];
//            }];
//            contactAppDevelopers.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
//            [rows addObject:contactAppDevelopers];
//
//            OBATableSection *section = [OBATableSection tableSectionWithTitle:NSLocalizedString(@"msg_contact_us", @"") rows:rows];
//
//            return section;
//        }
    }

    private func addAbout() {
        // Header
        addTableHeaderToStack(headerText: NSLocalizedString("more_controller.about_app", value: "About this App", comment: "Header for a section that shows the user information about this app."))

        // Credits
        let credits = DefaultTableRowView(title: NSLocalizedString("more_controller.credits_row_title", value: "Credits", comment: "Credits - like who should get credit for creating this."), accessoryType: .disclosureIndicator)
        addTableRowToStack(credits)
        stackView.setTapHandler(forRow: credits) { _ in
            // TODO
        }

        // Privacy
        let privacy = DefaultTableRowView(title: NSLocalizedString("more_controller.privacy_row_title", value: "Privacy Policy", comment: "A link to the app's Privacy Policy"), accessoryType: .disclosureIndicator)
        addTableRowToStack(privacy)
        stackView.setTapHandler(forRow: privacy) { [weak self] _ in
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
        addTableRowToStack(weather, isLastRow: true)
        stackView.setTapHandler(forRow: weather) { [weak self] _ in
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

}
