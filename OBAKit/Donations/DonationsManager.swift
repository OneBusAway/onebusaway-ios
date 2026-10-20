//
//  DonationsManager.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 10/30/23.
//

import Foundation
import OBAKitCore
import StoreKit
import SwiftUI

/// Manages the visibility of donation requests.
public class DonationsManager {

    /// Creates a new DonationsManager object.
    /// - Parameters:
    ///   - bundle: The application bundle. Usually, `Bundle.main`
    ///   - userDefaults: The user defaults object.
    ///   - analytics: The Analytics object.
    ///   - appLaunchCount: Returns the number of times the app has been launched.
    ///   - storefrontCountryCode: Returns the App Store storefront's ISO 3166-1 alpha-3
    ///     country code, or `nil` when it can't be determined.
    public init(
        bundle: Bundle,
        userDefaults: UserDefaults,
        obacoService: ObacoAPIService?,
        analytics: Analytics?,
        appLaunchCount: @escaping () -> Int,
        storefrontCountryCode: @escaping () async -> String? = { await Storefront.current?.countryCode }
    ) {
        self.bundle = bundle
        self.userDefaults = userDefaults
        self.analytics = analytics
        self.appLaunchCount = appLaunchCount
        self.storefrontCountryCode = storefrontCountryCode

        Task { [weak self] in
            await self?.refreshStorefront()
            // The rider can switch App Store country while the app runs; re-read
            // it then, or the gate stays on the old storefront until relaunch.
            for await _ in Storefront.updates {
                guard let self else { return }
                await self.refreshStorefront()
            }
        }
    }

    // MARK: - Data

    private let bundle: Bundle
    var obacoService: ObacoAPIService?
    private let analytics: Analytics?
    private let appLaunchCount: () -> Int
    private let storefrontCountryCode: () async -> String?

    // MARK: - User Defaults

    private let userDefaults: UserDefaults
    private static let donationRequestDismissedDateKey = "donationRequestDismissedDateKey"
    private static let donationRequestReminderDateKey = "donationRequestReminderDateKey"
    private static let storefrontAllowsDonationsKey = "donationsStorefrontAllowsDonationsKey"

    // MARK: - Storefront

    /// Whether the App Store storefront lets the app ask for donations.
    ///
    /// Only the United States storefront may link out to a payment page other than
    /// In-App Purchase (guideline 3.1.1(a)); App Review rejected 26.4 for showing
    /// the donation link elsewhere. Cached in user defaults so it is known at
    /// launch, before `Storefront.current` answers; `false` until it has answered once.
    var storefrontAllowsDonations: Bool {
        userDefaults.bool(forKey: DonationsManager.storefrontAllowsDonationsKey)
    }

    /// Re-reads the storefront. An unknown storefront keeps the last known answer.
    func refreshStorefront() async {
        guard let countryCode = await storefrontCountryCode() else { return }
        userDefaults.set(countryCode == "USA", forKey: DonationsManager.storefrontAllowsDonationsKey)
    }

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

    /// The app ships donations and the storefront allows them.
    private var donationsAllowed: Bool {
        bundle.donationsEnabled && storefrontAllowsDonations
    }

    public var donationsEnabled: Bool {
        donationsAllowed && obacoService != nil
    }

    /// The minimum number of app launches required before donation requests are shown.
    private static let minimumAppLaunchesBeforeRequestingDonations = 3

    /// When true, it means the app should show an inline donation request UI.
    public var shouldRequestDonations: Bool {
        guard donationsAllowed else { return false }

        if appLaunchCount() < DonationsManager.minimumAppLaunchesBeforeRequestingDonations { return false }

        if let donationRequestReminderDate = donationRequestReminderDate, donationRequestReminderDate.timeIntervalSinceNow > 0 {
            return false
        }

        return donationRequestDismissedDate == nil
    }

    // MARK: - UI

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

        return DonationLearnMoreView()
            .environmentObject(donationModel)
            .environmentObject(AnalyticsModel(analytics))
    }
}
