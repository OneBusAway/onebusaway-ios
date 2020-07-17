//
//  ContactUsHelper.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MessageUI
import CoreTelephony

enum EmailTarget: Int {
    case transitAgency, appDevelopers
}

/// Helps to create feedback emails directed at either the app developers or current transit agency.
class ContactUsHelper: NSObject {

    private let application: Application

    /// Creates a new instance of `ContactUsHelper`
    /// - Parameter application: The OBA application object
    init(application: Application) {
        self.application = application

        super.init()
    }

    /// Creates an `MFMailComposeViewController` populated with the correct email address, message, and subject for `target`.
    /// - Parameter target: The target of the message—app developers or transit agency.
    /// - Note: If Mail.app is not configured to send email, then this method will return `nil`.
    public func buildMailComposer(target: EmailTarget) -> MFMailComposeViewController? {
        guard MFMailComposeViewController.canSendMail() else {
            return nil
        }

        let mailComposer = MFMailComposeViewController()

        if target == .appDevelopers {
            mailComposer.setToRecipients([appDevelopersEmail])
            mailComposer.setSubject(OBALoc("contact_use_helper.feedback_subject.app", value: "OneBusAway Feedback", comment: "Feedback email template subject for the app developers"))
            mailComposer.setMessageBody(appDevelopersMessageTemplate, isHTML: true)
        }
        else {
            mailComposer.setToRecipients([application.currentRegion?.contactEmail ?? "contact@onebusaway.org"])
            mailComposer.setSubject(OBALoc("contact_use_helper.feedback_subject.transit_agency", value: "Transit Rider Feedback", comment: "Feedback email template subject for the transit agency"))
            mailComposer.setMessageBody(transitAgencyMessageTemplate, isHTML: true)
        }

        return mailComposer
    }

    /// Creates an alert from which the user can copy the same information as exists in the body of the mail composer created in `buildMailComposer()`
    /// - Parameter target: The target of the message—app developers or transit agency.
    func buildCantSendEmailAlert(target: EmailTarget) -> UIAlertController {
        let email = emailAddress(for: target)
        let title = OBALoc("contact_us_helper.cant_send_email.title", value: "Can't Send Email via Mail.app", comment: "Title of the alert that appears when the user's device isn't configured to send email.")
        let bodyFormat = OBALoc("contact_us_helper.cant_send_email.body_fmt", value: "In order to contact us, you'll need to email us at %@. Please tap 'Copy Debug Info' to copy information to the clipboard that will be helpful for us to fix this problem. Please include this information in your email.", comment: "Body of the the alert that appears when you try sending an email without Mail.app set up")

        let alert = UIAlertController(title: title, message: String(format: bodyFormat, email), preferredStyle: .alert)

        alert.addAction(title: OBALoc("contact_us_helper.cant_send_email.copy_email_button", value: "Copy Email Address", comment: "A button that lets the user copy an email address to the clipboard.")) { _ in
            UIPasteboard.general.string = email
        }

        alert.addAction(title: OBALoc("contact_us_helper.cant_send_email.copy_message_button", value: "Copy Debug Info", comment: "A button that lets the user copy a default message, including debug info, to the clipboard.")) { [weak self] _ in
            guard
                let self = self,
                let data = self.messageTemplate(for: target).data(using: .utf8),
                let str = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            else { return }

            UIPasteboard.general.set(attributedString: str)
        }

        alert.addAction(UIAlertAction.cancelAction)

        return alert
    }

    // MARK: - App Developers

    var appDevelopersMessageTemplate: String {
        let template = """
        <html><body>
        <p>How can we help? Please enter your response below:</p>
        <p style='border: solid 1px #ccc'>
        <br><br><br>
        </p>
        <hr>
        <p>The following information is provided for troubleshooting purposes.
           If you are uncomfortable sharing any of the following information
           you may remove it, however it may affect our ability to assist you.
        </p>
        <ul>{{DEBUGGING_INFO}}</ul>
        </body></html>
        """

        var debuggingInfoListItems = ""
        for val in debuggingInfo {
            debuggingInfoListItems += String(format: "<li>%@ = <strong>%@</strong></li>\r\n", val.label, val.value)
        }

        return template.replacingOccurrences(of: "{{DEBUGGING_INFO}}", with: debuggingInfoListItems)
    }

    var appDevelopersEmail: String {
        Bundle.main.appDevelopersEmailAddress ?? "iphone-app@onebusaway.org"
    }

    // MARK: - Transit Agency

    var transitAgencyMessageTemplate: String {
        return "<p>How can we help? Please enter your response below:</p><p></p>"
    }

    var transitAgencyEmail: String {
        application.currentRegion?.contactEmail ?? "contact@onebusaway.org"
    }

    // MARK: - Disambiguators

    private func emailAddress(for target: EmailTarget) -> String {
        if target == .appDevelopers {
            return appDevelopersEmail
        }
        else {
            return transitAgencyEmail
        }
    }

    private func messageTemplate(for target: EmailTarget) -> String {
        if target == .appDevelopers {
            return appDevelopersMessageTemplate
        }
        else {
            return transitAgencyMessageTemplate
        }
    }

    // MARK: - Private Helpers

    private struct AppDebugValue {
        let label: String
        let value: String
    }

    private var debuggingInfo: [AppDebugValue] {
        var values = [AppDebugValue]()

        // App/Settings
        values.append(AppDebugValue(label: "App Version", value: Bundle.main.appVersion))
        values.append(AppDebugValue(label: "OS Version", value: UIDevice.current.systemVersion))
        values.append(AppDebugValue(label: "Locale", value: Locale.current.languageCode ?? "None"))
        values.append(AppDebugValue(label: "VoiceOver Running", value: String(UIAccessibility.isVoiceOverRunning)))
        values.append(AppDebugValue(label: "Bookmark Count", value: String(application.userDataStore.bookmarks.count)))

        // Notifications
        values.append(AppDebugValue(label: "Registered for Notifications", value: String(application.isRegisteredForRemoteNotifications)))

        // Location
        values.append(AppDebugValue(label: "Location Authorization", value: String(application.locationService.authorizationStatus)))

        if let currentLocation = application.locationService.currentLocation {
            let str = "(\(currentLocation.coordinate.latitude),\(currentLocation.coordinate.longitude))"
            values.append(AppDebugValue(label: "Current Location", value: str))
        }
        else {
            values.append(AppDebugValue(label: "Current Location", value: "N/A"))
        }

        // Region
        if let region = application.currentRegion {
            values.append(AppDebugValue(label: "Region", value: region.name))
            values.append(AppDebugValue(label: "Region ID", value: String(region.regionIdentifier)))
            values.append(AppDebugValue(label: "Base API URL", value: region.OBABaseURL.absoluteString))
        }
        else {
            values.append(AppDebugValue(label: "Region", value: "No Region Selected"))
        }

        // Device/Network
        values.append(AppDebugValue(label: "Device", value: UIDevice.current.modelName))

        return values
    }
}
