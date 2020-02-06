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
import OBAKitCore

/// Provides access to OneBusAway Settings (Region configuration, etc.)
@objc(OBAMoreViewController) public class MoreViewController: UIViewController, AloeStackTableBuilder, MFMailComposeViewControllerDelegate, RegionsServiceDelegate, FarePaymentsDelegate {

    /// The OBA application object
    private let application: Application

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.groupedTableBackground
    )

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

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)

        reloadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        regionPickerRow.subtitleLabel.text = application.currentRegion?.name ?? ""
    }

    /// Reloads the stack view from scratch
    private func reloadData() {
        stackView.removeAllRows()

        addHeader()

        if application.userDataStore.debugMode {
            addDebug()
        }

        addUpdatesAndAlerts()
        addMyLocationSection()
        addAbout()

        refreshTableData()
    }

    /// Refreshes individual rows whose data might change between presentations of this controller.
    private func refreshTableData() {
        if let region = application.currentRegion {
            regionPickerRow.subtitleLabel.text = region.name
            let fmtString = OBALoc("more_controller.updates_and_alerts.row_fmt", value: "Alerts for %@", comment: "Alerts for {Region Name}")
            alertsForRegionRow.titleLabel.text = String(format: fmtString, region.name)
        }
    }

    // MARK: - Actions

    @objc func showSettings() {
        let settingsController = SettingsViewController(application: application)
        let navigation = application.viewRouter.buildNavigation(controller: settingsController)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - Controller Header

    private lazy var moreHeaderController = MoreHeaderViewController(application: application)

    private func addHeader() {
        prepareChildController(moreHeaderController) {
            stackView.addRow(moreHeaderController.view, hideSeparator: true, insets: .zero)
        }
    }

    // MARK: - UI Builders

    // MARK: - Regional Alerts Section

    private lazy var alertsForRegionRow = DefaultTableRowView(title: OBALoc("more_controller.alerts_for_region", value: "Alerts", comment: "Alerts for region row in the More controller"), accessoryType: .disclosureIndicator)

    private func addUpdatesAndAlerts() {
        addGroupedTableHeaderToStack(headerText: OBALoc("more_controller.updates_and_alerts.header", value: "Updates and Alerts", comment: "Updates and Alerts header text"))

        addGroupedTableRowToStack(alertsForRegionRow, isLastRow: true) { [weak self] _ in
            guard let self = self else { return }
            let alertsController = AgencyAlertsViewController(application: self.application)
            self.application.viewRouter.navigate(to: alertsController, from: self)
        }
    }

    // MARK: - My Location Section

    private func addMyLocationSection() {
        addGroupedTableHeaderToStack(headerText: OBALoc("more_controller.my_location.header", value: "My Location", comment: "'My Location' section header on the 'More' controller."))

        addRegionPickerRowToStackView()

        if let currentRegion = application.currentRegion, currentRegion.supportsMobileFarePayment {
            addPayMyFareRowToStackView()
        }

        addAgenciesRowToStackView()
    }

    private func addRegionPickerRowToStackView() {
        addGroupedTableRowToStack(regionPickerRow) { [weak self] _ in
            guard let self = self else { return }
            self.showRegionPicker()
        }
    }

    private lazy var regionPickerRow: ValueTableRowView = {
        let regionRowTitle = OBALoc("more_controller.my_location.region_row_title", value: "Region", comment: "Title of the row that lets the user choose their current region.")
        let row = ValueTableRowView(title: regionRowTitle, subtitle: "", accessoryType: .disclosureIndicator)
        row.layoutMargins = ThemeMetrics.groupedRowLayoutMargins
        row.backgroundColor = ThemeColors.shared.groupedTableRowBackground

        return row
    }()

    private func showRegionPicker() {
        let regionPicker = RegionPickerViewController(application: application)
        let nav = application.viewRouter.buildNavigation(controller: regionPicker)
        application.viewRouter.present(nav, from: self)
    }

    private func addPayMyFareRowToStackView() {
        let rowTitle = OBALoc("more_controller.my_location.pay_fare", value: "Pay My Fare", comment: "Title of the mobile fare payment row")
        let payMyFareRow = DefaultTableRowView(title: rowTitle, accessoryType: .none)
        addGroupedTableRowToStack(payMyFareRow) { [weak self] _ in
            guard let self = self else { return }
            self.logRowTapAnalyticsEvent(name: "Pay Fare")
            self.farePayments.beginFarePaymentsWorkflow()
        }
    }

    private func addAgenciesRowToStackView() {
        let rowTitle = OBALoc("more_controller.my_location.agencies", value: "Agencies", comment: "Title of the Agencies row in the My Location section")
        let row = DefaultTableRowView(title: rowTitle, accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(row, isLastRow: true) { [weak self] _ in
            guard let self = self else { return }
            self.logRowTapAnalyticsEvent(name: "Show Agencies")
            let agencies = AgenciesViewController(application: self.application)
            self.application.viewRouter.navigate(to: agencies, from: self)
        }
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

    private func addAbout() {
        // Header
        addGroupedTableHeaderToStack(headerText: OBALoc("more_controller.about_app", value: "About this App", comment: "Header for a section that shows the user information about this app."))

        // Credits
        let credits = DefaultTableRowView(title: OBALoc("more_controller.credits_row_title", value: "Credits", comment: "Credits - like who should get credit for creating this."), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(credits) { [weak self] _ in
            guard let self = self else { return }
            let credits = CreditsViewController(application: self.application)
            self.application.viewRouter.navigate(to: credits, from: self)
        }

        // Privacy
        let privacy = DefaultTableRowView(title: OBALoc("more_controller.privacy_row_title", value: "Privacy Policy", comment: "A link to the app's Privacy Policy"), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(privacy) { [weak self] _ in
            guard
                let self = self,
                let url = Bundle.main.privacyPolicyURL
            else { return }

            let safari = SFSafariViewController(url: url)
            self.application.viewRouter.present(safari, from: self)
        }

        // Weather
        let weather = DefaultTableRowView(title: OBALoc("more_controller.weather_credits_row", value: "Weather forecasts powered by Dark Sky", comment: "Weather forecast attribution"), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(weather, isLastRow: true) { [weak self] _ in
            guard let self = self else { return }
            self.application.open(URL(string: "https://darksky.net/poweredby/")!, options: [:], completionHandler: nil)
        }
    }

    private func addDebug() {
        addGroupedTableHeaderToStack(headerText: OBALoc("more_controller.debug_section.header", value: "Debug", comment: "Section title for debugging helpers"))

        if application.shouldShowCrashButton {
            let crashRow = DefaultTableRowView(title: OBALoc("more_controller.debug_section.crash_row", value: "Crash the App", comment: "Title for a button that will crash the app."), accessoryType: .none)
            addGroupedTableRowToStack(crashRow) { [weak self] _ in
                guard let self = self else { return }
                self.application.performTestCrash()
            }

            let pushID = application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")
            let pushIDRow = ValueTableRowView(title: OBALoc("more_controller.debug_section.push_id.title", value: "Push ID", comment: "Title for the Push Notification ID row in the More Controller"), subtitle: pushID, accessoryType: .none)
            addGroupedTableRowToStack(pushIDRow) { [weak self] _ in
                if let pushID = self?.application.pushService?.pushUserID {
                    UIPasteboard.general.string = pushID
                }
            }
        }
    }

    // MARK: - Fare Payments

    private lazy var farePayments = FarePayments(application: application, delegate: self)

    public func farePayments(_ farePayments: FarePayments, present viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
        application.viewRouter.present(viewController, from: self, isModal: true)
    }

    public func farePayments(_ farePayments: FarePayments, present error: Error) {
        AlertPresenter.show(error: error, presentingController: self)
    }

    // MARK: - Regions Service Delegate

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        refreshTableData()
    }

    // MARK: - Private Helpers

    private func logRowTapAnalyticsEvent(name: String) {
        application.analytics?.logEvent?(name: "infoRowTapped", parameters: ["row": name])
    }
}
