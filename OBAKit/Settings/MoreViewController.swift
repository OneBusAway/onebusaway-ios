//
//  MoreViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MessageUI
import OBAKitCore
import SafariServices

/// Provides access to OneBusAway Settings (Region configuration, etc.)
@objc(OBAMoreViewController)
public class MoreViewController: UIViewController,
    AppContext,
    FarePaymentsDelegate,
    OBAListViewDataSource,
    MFMailComposeViewControllerDelegate,
    RegionsServiceDelegate {

    // MARK: - Stores
    public let application: Application

    /// A helper object that crafts support emails or alerts when the user's email client isn't configured properly.
    private lazy var contactUsHelper = ContactUsHelper(application: application)

    // MARK: - UI elements
    var listView = OBAListView()

    // MARK: - Init
    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("more_controller.title", value: "More", comment: "Title of the More tab")
        tabBarItem.image = Icons.moreTabIcon
        tabBarItem.selectedImage = Icons.moreSelectedTabIcon

        let contactUs = OBALoc("more_controller.contact_us", value: "Contact Us", comment: "A button to contact transit agency/developers.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: contactUs, style: .plain, target: self, action: #selector(showContactUsDialog(_:)))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.settings, style: .plain, target: self, action: #selector(showSettings))

        application.regionsService.addDelegate(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController
    public override func viewDidLoad() {
        super.viewDidLoad()

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        view.backgroundColor = ThemeColors.shared.systemBackground

        self.listView.register(listViewItem: MoreHeaderItem.self)
        self.listView.applyData(animated: false)
    }

    // MARK: - Sections
    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [
            headerSection,
            debugSection,
            updatesAndAlertsSection,
            myLocationSection,
            helpOutSection,
            aboutSection
        ].compactMap { $0 }
    }

    // MARK: Header section
    var headerSection: OBAListViewSection {
        return OBAListViewSection(id: "header", contents: [MoreHeaderItem(onSelectAction: { _ in self.toggleDebug() })])
    }

    func toggleDebug() {
        self.application.userDataStore.debugMode.toggle()
        self.listView.applyData()

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

    // MARK: Updates and alerts section
    var updatesAndAlertsSection: OBAListViewSection {
        let header = OBALoc(
            "more_controller.updates_and_alerts.header",
            value: "Updates and Alerts",
            comment: "Updates and Alerts header text")

        let row = OBALoc(
            "more_controller.alerts_for_region",
            value: "Alerts",
            comment: "Alerts for region row in the More controller")

        return OBAListViewSection(id: "updates_and_alerts", title: header, contents: [
            OBAListRowView.DefaultViewModel(title: row, onSelectAction: { _ in
                self.application.viewRouter.navigate(to: AgencyAlertsViewController(application: self.application), from: self)
            })
        ])
    }

    // MARK: My location section
    var myLocationSection: OBAListViewSection {
        var contents: [AnyOBAListViewItem] = []

        contents.append(OBAListRowView.ValueViewModel(title: OBALoc("more_controller.my_location.region_row_title", value: "Region", comment: "Title of the row that lets the user choose their current region."), subtitle: application.currentRegion?.name, onSelectAction: { [unowned self] _ in

            let regionPicker = UIHostingController(
                rootView: NavigationView {
                    RegionPickerView(regionProvider: RegionPickerCoordinator(regionsService: self.application.regionsService))
                        .interactiveDismissDisabled()
                }.navigationViewStyle(.stack)
            )

            self.application.viewRouter.present(regionPicker, from: self)
        }).typeErased)

        if let currentRegion = application.currentRegion, currentRegion.supportsMobileFarePayment {
            contents.append(OBAListRowView.DefaultViewModel(title: OBALoc("more_controller.my_location.pay_fare", value: "Pay My Fare", comment: "Title of the mobile fare payment row"), onSelectAction: { _ in
                self.logRowTapAnalyticsEvent(name: "Pay Fare")
                self.farePayments.beginFarePaymentsWorkflow()
            }).typeErased)
        }

        contents.append(OBAListRowView.DefaultViewModel(title: OBALoc("more_controller.my_location.agencies", value: "Agencies", comment: "Title of the Agencies row in the My Location section"), onSelectAction: { _ in
            self.logRowTapAnalyticsEvent(name: "Show Agencies")
            let agencies = AgenciesViewController(application: self.application)
            self.application.viewRouter.navigate(to: agencies, from: self)
        }).typeErased)

        return OBAListViewSection(id: "my_location", title: OBALoc("more_controller.my_location.header", value: "My Location", comment: "'My Location' section header on the 'More' controller."), contents: contents)
    }

    // MARK: About section
    var aboutSection: OBAListViewSection {
        let header = OBALoc(
            "more_controller.about_app",
            value: "About this App",
            comment: "Header for a section that shows the user information about this app.")

        return OBAListViewSection(id: "about", title: header, contents: [
            OBAListRowView.DefaultViewModel(
                title: OBALoc(
                    "more_controller.credits_row_title",
                    value: "Credits",
                    comment: "Credits - like who should get credit for creating this."),
                onSelectAction: { _ in
                    let credits = CreditsViewController(application: self.application)
                    self.application.viewRouter.navigate(to: credits, from: self)
                }),

            OBAListRowView.DefaultViewModel(
                title: OBALoc(
                    "more_controller.privacy_row_title",
                    value: "Privacy Policy",
                    comment: "A link to the app's Privacy Policy"),
                onSelectAction: { _ in
                    guard let url = Bundle.main.privacyPolicyURL else { return }
                    let safari = SFSafariViewController(url: url)
                    self.application.viewRouter.present(safari, from: self)
                }),

            OBAListRowView.DefaultViewModel(
                title: OBALoc(
                    "more_controller.weather_credits_row",
                    value: "Weather forecasts powered by Dark Sky",
                    comment: "Weather forecast attribution"),
                onSelectAction: { _ in
                    self.application.open(URL(string: "https://darksky.net/poweredby/")!, options: [:], completionHandler: nil)
                })
        ])
    }

    // MARK: - Help Out section
    var helpOutSection: OBAListViewSection {
        let header = OBALoc(
            "more_controller.help_out",
            value: "Help make the app better",
            comment: "Header for the volunteer section.")

        return OBAListViewSection(id: "help_out", title: header, contents: [
            OBAListRowView.DefaultViewModel(
                title: OBALoc(
                    "more_controller.translate_the_app",
                    value: "Help Translate the App",
                    comment: "Request to help localize OneBusAway"),
                onSelectAction: { _ in
                    let url = URL(string: "https://www.transifex.com/open-transit-software-foundation/onebusaway-ios/")!
                    self.application.open(url, options: [:], completionHandler: nil)
                }),

            OBAListRowView.DefaultViewModel(
                title: OBALoc(
                    "more_controller.develop_the_app",
                    value: "Help Fix Bugs & Build New Features",
                    comment: "Request to help develop the app"),
                onSelectAction: { _ in
                    let url = URL(string: "https://github.com/oneBusAway/onebusaway-ios")!
                    self.application.open(url, options: [:], completionHandler: nil)
                }),
        ])
    }

    // MARK: Debug section
    var debugSection: OBAListViewSection? {
        guard application.userDataStore.debugMode else { return nil }
        var contents: [AnyOBAListViewItem] = []
        if application.shouldShowCrashButton {
            let crashApp = OBALoc(
                "more_controller.debug_section.crash_row",
                value: "Crash the App",
                comment: "Title for a button that will crash the app.")

            contents.append(OBAListRowView.DefaultViewModel(title: crashApp, onSelectAction: { _ in
                self.application.performTestCrash()
            }).typeErased)
        }

        let pushIDTitle = OBALoc(
            "more_controller.debug_section.push_id.title",
            value: "Push ID",
            comment: "Title for the Push Notification ID row in the More Controller")

        let pushID = application.pushService?.pushUserID ?? OBALoc("more_controller.debug_section.push_id.not_available", value: "Not available", comment: "This is displayed instead of the user's push ID if the value is not available.")

        contents.append(OBAListRowView.ValueViewModel(title: pushIDTitle, subtitle: pushID, onSelectAction: { _ in
            if let pushID = self.application.pushService?.pushUserID {
                UIPasteboard.general.string = pushID
            }
        }).typeErased)

        return OBAListViewSection(id: "debug", title: OBALoc("more_controller.debug_section.header", value: "Debug", comment: "Section title for debugging helpers"), contents: contents)
    }

    // MARK: - Actions

    @objc func showSettings() {
        let settingsController = SettingsViewController(application: application)
        let navigation = application.viewRouter.buildNavigation(controller: settingsController)
        application.viewRouter.present(navigation, from: self)
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

    @objc func showContactUsDialog(_ sender: UIBarButtonItem) {
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

        application.viewRouter.present(
            sheet,
            from: self,
            isPopover: traitCollection.userInterfaceIdiom == .pad,
            popoverBarButtonItem: sender
        )
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
        self.listView.applyData()
    }

    // MARK: - Private Helpers

    private func logRowTapAnalyticsEvent(name: String) {
        application.analytics?.logEvent?(name: "infoRowTapped", parameters: ["row": name])
    }
}
