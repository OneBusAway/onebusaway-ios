//
//  MoreViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/27/19.
//

import UIKit
import IGListKit
import SafariServices
import MessageUI
import OBAKitCore

/// Provides access to OneBusAway Settings (Region configuration, etc.)
@objc(OBAMoreViewController)
public class MoreViewController: UIViewController,
    AppContext,
    FarePaymentsDelegate,
    HasTableStyle,
    ListAdapterDataSource,
    MFMailComposeViewControllerDelegate,
    RegionsServiceDelegate {

    /// The OBA application object
    public let application: Application

    /// A helper object that crafts support emails or alerts when the user's email client isn't configured properly.
    private lazy var contactUsHelper = ContactUsHelper(application: application)

    /// Creates a Settings controller
    /// - Parameter application: The OBA application object
    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("more_controller.title", value: "More", comment: "Title of the More tab")
        tabBarItem.image = Icons.moreTabIcon

        let contactUs = OBALoc("more_controller.contact_us", value: "Contact Us", comment: "A button to contact transit agency/developers.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: contactUs, style: .plain, target: self, action: #selector(showContactUsDialog))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.settings, style: .plain, target: self, action: #selector(showSettings))

        application.regionsService.addDelegate(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionController.reload(animated: false)
    }

    // MARK: - IGListKit

    private lazy var collectionController = CollectionController(application: application, dataSource: self, style: tableStyle)

    var tableStyle: TableCollectionStyle { .grouped }

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        return [
            moreHeaderSection,
            debugSection,
            updatesAndAlertsSection,
            myLocationSection,
            aboutSection
        ].compactMap { $0 }
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        switch object {
        case is MoreHeaderSection:
            return MoreHeaderSectionController(formatters: application.formatters, style: tableStyle)
        default:
            return defaultSectionController(for: object)
        }
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    // MARK: - Header Section

    private lazy var moreHeaderSection = MoreHeaderSection { [weak self] in
        guard let self = self else { return }

        self.application.userDataStore.debugMode.toggle()
        self.collectionController.reload(animated: true)

        let title: String
        if self.application.userDataStore.debugMode {
            title = OBALoc("more_header.debug_enabled.title", value: "Debug Mode Enabled", comment: "Title of the alert that tells the user they've enabled debug mode.")
        }
        else {
            title = OBALoc("more_header.debug_disabled.title", value: "Debug Mode Disabled", comment: "Title of the alert that tells the user they've disabled debug mode.")
        }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction.dismissAction)
        self.present(alert, animated: true, completion: nil)
    }

    // MARK: - Actions

    @objc func showSettings() {
        let settingsController = SettingsViewController(application: application)
        let navigation = application.viewRouter.buildNavigation(controller: settingsController)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - Regional Alerts Section

    private var updatesAndAlertsSection: TableSectionData {
        let tableRow = TableRowData(title: OBALoc("more_controller.alerts_for_region", value: "Alerts", comment: "Alerts for region row in the More controller"), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let alertsController = AgencyAlertsViewController(application: self.application)
            self.application.viewRouter.navigate(to: alertsController, from: self)
        }

        return TableSectionData(title: OBALoc("more_controller.updates_and_alerts.header", value: "Updates and Alerts", comment: "Updates and Alerts header text"), rows: [tableRow])
    }

    // MARK: - My Location Section

    private var myLocationSection: TableSectionData {
        var rows = [TableRowData]()

        let picker = TableRowData(title: OBALoc("more_controller.my_location.region_row_title", value: "Region", comment: "Title of the row that lets the user choose their current region."), value: application.currentRegion?.name, accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let regionPicker = RegionPickerViewController(application: self.application)
            let nav = self.application.viewRouter.buildNavigation(controller: regionPicker)
            self.application.viewRouter.present(nav, from: self)
        }
        rows.append(picker)

        if let currentRegion = application.currentRegion, currentRegion.supportsMobileFarePayment {
            let payMyFare = TableRowData(title: OBALoc("more_controller.my_location.pay_fare", value: "Pay My Fare", comment: "Title of the mobile fare payment row"), accessoryType: .none) { [weak self] _ in
                guard let self = self else { return }
                self.logRowTapAnalyticsEvent(name: "Pay Fare")
                self.farePayments.beginFarePaymentsWorkflow()
            }
            rows.append(payMyFare)
        }

        let agencies = TableRowData(title: OBALoc("more_controller.my_location.agencies", value: "Agencies", comment: "Title of the Agencies row in the My Location section"), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            self.logRowTapAnalyticsEvent(name: "Show Agencies")
            let agencies = AgenciesViewController(application: self.application)
            self.application.viewRouter.navigate(to: agencies, from: self)
        }
        rows.append(agencies)

        return TableSectionData(title: OBALoc("more_controller.my_location.header", value: "My Location", comment: "'My Location' section header on the 'More' controller."), rows: rows)
    }

    // MARK: - Contact Us Button

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
        let sheetTitle = OBALoc("more_controller.contact_us_alert_title", value: "Contact Us", comment: "Contact Us alert title.")
        let sheet = UIAlertController(title: sheetTitle, message: nil, preferredStyle: .actionSheet)

        // Contact Developers
        sheet.addAction(title: OBALoc("more_controller.contact_developers", value: "Feature Request/Bug Report", comment: "Title of the action sheet option for contacting the developers of the app.")) { [weak self] _ in
            guard let self = self else { return }
            self.application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.reportProblem, value: "feedback_app_feedback_email")
            self.presentEmailFeedbackForm(target: .appDevelopers)
        }

        // Contact Transit Agency
        sheet.addAction(title: OBALoc("more_controller.contact_transit", value: "Vehicle/Schedule Problem", comment: "Title of the action sheet option for contacting a user's transit agency.")) { [weak self] _ in
            guard let self = self else { return }
            self.application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.reportProblem, value: "feedback_customer_service")
            self.presentEmailFeedbackForm(target: .transitAgency)
        }

        sheet.addAction(UIAlertAction.cancelAction)

        present(sheet, animated: true, completion: nil)
    }

    // MARK: - About Section

    private var aboutSection: TableSectionData {
        var rows = [TableRowData]()

        let credits = TableRowData(title: OBALoc("more_controller.credits_row_title", value: "Credits", comment: "Credits - like who should get credit for creating this."), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let credits = CreditsViewController(application: self.application)
            self.application.viewRouter.navigate(to: credits, from: self)
        }
        rows.append(credits)

        let privacy = TableRowData(title: OBALoc("more_controller.privacy_row_title", value: "Privacy Policy", comment: "A link to the app's Privacy Policy"), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard
                let self = self,
                let url = Bundle.main.privacyPolicyURL
            else { return }

            let safari = SFSafariViewController(url: url)
            self.application.viewRouter.present(safari, from: self)
        }
        rows.append(privacy)

        // Weather
        let weather = TableRowData(title: OBALoc("more_controller.weather_credits_row", value: "Weather forecasts powered by Dark Sky", comment: "Weather forecast attribution"), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            self.application.open(URL(string: "https://darksky.net/poweredby/")!, options: [:], completionHandler: nil)
        }
        rows.append(weather)

        return TableSectionData(title: OBALoc("more_controller.about_app", value: "About this App", comment: "Header for a section that shows the user information about this app."), rows: rows)
    }

    // MARK: - Debug Section

    private var debugSection: TableSectionData? {
        guard application.userDataStore.debugMode else {
            return nil
        }

        var rows = [TableRowData]()

        // Crash Row
        if application.shouldShowCrashButton {
            let crashRow = TableRowData(title: OBALoc("more_controller.debug_section.crash_row", value: "Crash the App", comment: "Title for a button that will crash the app."), accessoryType: .none) { [weak self] _ in
                guard let self = self else { return }
                self.application.performTestCrash()
            }
            rows.append(crashRow)
        }

        // Push ID Row
        let pushID = application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")
        let pushIDRow = TableRowData(title: OBALoc("more_controller.debug_section.push_id.title", value: "Push ID", comment: "Title for the Push Notification ID row in the More Controller"), value: pushID, accessoryType: .none) { [weak self] _ in
            guard let self = self else { return }
            if let pushID = self.application.pushService?.pushUserID {
                UIPasteboard.general.string = pushID
            }
        }
        rows.append(pushIDRow)

        return TableSectionData(title: OBALoc("more_controller.debug_section.header", value: "Debug", comment: "Section title for debugging helpers"), rows: rows)
    }

    // MARK: - Fare Payments

    private lazy var farePayments = FarePayments(application: application, delegate: self)

    public func farePayments(_ farePayments: FarePayments, present viewController: UIViewController, animated: Bool, completion: VoidBlock?) {
        application.viewRouter.present(viewController, from: self, isModal: true)
    }

    public func farePayments(_ farePayments: FarePayments, present error: Error) {
        AlertPresenter.show(error: error, presentingController: self)
    }

    // MARK: - Regions Service Delegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        collectionController.reload(animated: false)
    }

    // MARK: - Private Helpers

    private func logRowTapAnalyticsEvent(name: String) {
        application.analytics?.logEvent?(name: "infoRowTapped", parameters: ["row": name])
    }
}
