//
//  DonationsManager.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 10/30/23.
//

import Foundation
import OBAKitCore
import SwiftUI

public enum DonationsUserDefaultsKeys: String, RawRepresentable {
    case forceStripeTestModeDefaultsKey = "forceStripeTestMode"
}

#if canImport(Stripe)
import StripeApplePay

/// Manages the visibility of donation requests.
public class DonationsManager {

    /// Creates a new DonationsManager object.
    /// - Parameters:
    ///   - bundle: The application bundle. Usually, `Bundle.main`
    ///   - userDefaults: The user defaults object.
    ///   - analytics: The Analytics object.
    public init(
        bundle: Bundle,
        userDefaults: UserDefaults,
        obacoService: ObacoAPIService?,
        analytics: Analytics?
    ) {
        self.bundle = bundle
        self.userDefaults = userDefaults
        self.analytics = analytics

        self.userDefaults.register(
            defaults: [DonationsUserDefaultsKeys.forceStripeTestModeDefaultsKey.rawValue: false]
        )
    }

    // MARK: - Data

    private let bundle: Bundle
    var obacoService: ObacoAPIService?
    private let analytics: Analytics?

    // MARK: - User Defaults

    private let userDefaults: UserDefaults
    private static let donationRequestDismissedDateKey = "donationRequestDismissedDateKey"
    private static let donationRequestReminderDateKey = "donationRequestReminderDateKey"

    // MARK: - Dismiss Donations Request

    /// The date that donation requests were hidden by the user, either because they donated or because they tapped the 'dismiss' button.
    public var donationRequestDismissedDate: Date? {
        get {
            userDefaults.object(forKey: DonationsManager.donationRequestDismissedDateKey) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: DonationsManager.donationRequestDismissedDateKey)
        }
    }

    /// Hides subsequent attempts to request donations.
    public func dismissDonationsRequests() {
        donationRequestDismissedDate = Date()
    }

    // MARK: - Donation Request Reminder

    /// Optional date at which the app should remind the user to donate.
    public var donationRequestReminderDate: Date? {
        get {
            userDefaults.object(forKey: DonationsManager.donationRequestReminderDateKey) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: DonationsManager.donationRequestReminderDateKey)
        }
    }

    /// Sets a date on which the app will remind the user to donate.
    public func remindUserLater() {
        donationRequestReminderDate = Date(timeIntervalSinceNow: 86400 * 14) // two weeks
    }

    // MARK: - State

    public var donationsEnabled: Bool {
        bundle.donationsEnabled && obacoService != nil
    }

    /// When true, it means the app should show an inline donation request UI.
    public var shouldRequestDonations: Bool {
        if !bundle.donationsEnabled { return false }

        if let donationRequestReminderDate = donationRequestReminderDate, donationRequestReminderDate.timeIntervalSinceNow > 0 {
            return false
        }

        return donationRequestDismissedDate == nil
    }

    // MARK: - Stripe Mode and Key

    public var stripeTestMode: Bool {
#if DEBUG
        return true
#else
        return userDefaults.bool(forKey: DonationsUserDefaultsKeys.forceStripeTestModeDefaultsKey.rawValue)
#endif
    }

    public var stripePublishableKey: String? {
        if stripeTestMode {
            bundle.stripePublishableTestKey
        }
        else {
            bundle.stripePublishableProductionKey
        }
    }

    public func refreshStripePublishableKey() {
        StripeAPI.defaultPublishableKey = stripePublishableKey
    }

    // MARK: - UI

    public static func buildDonationThankYouAlert() -> UIAlertController {
        let alert = UIAlertController(
            title: Strings.donationThankYouTitle,
            message: Strings.donationThankYouBody,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.dismiss, style: .default))

        return alert
    }

    func buildObservableDonationModel(donationPushNotificationID: String? = nil) -> DonationModel? {
        guard donationsEnabled, let obacoService else {
            return nil
        }

        return DonationModel(
            obacoService: obacoService,
            donationsManager: self,
            analytics: analytics,
            donationPushNotificationID: donationPushNotificationID
        )
    }

    func buildLearnMoreView(presentingController: UIViewController, donationPushNotificationID: String? = nil) -> some View {
        guard let donationModel = buildObservableDonationModel(donationPushNotificationID: donationPushNotificationID) else {
            fatalError()
        }

        return DonationLearnMoreView { donated in
            guard donated else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                presentingController.present(DonationsManager.buildDonationThankYouAlert(), animated: true)
            }
        }
        .environmentObject(donationModel)
        .environmentObject(AnalyticsModel(analytics))
    }
}
#else
public class DonationsManager {
    public init(
        bundle: Bundle,
        userDefaults: UserDefaults,
        obacoService: ObacoAPIService?,
        analytics: Analytics?
    ) {}

    public var donationsEnabled: Bool {
        false
    }

    public var shouldRequestDonations: Bool {
        false
    }

    public func dismissDonationsRequests() {}

    public func remindUserLater() {}

    public func refreshStripePublishableKey() {}
}
#endif
