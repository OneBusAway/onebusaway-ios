//
//  DonationsManager.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 10/30/23.
//

import Foundation

/// Manages the visibility of donation requests.
public class DonationsManager {

    /// Creates a new DonationsManager object.
    /// - Parameters:
    ///   - bundle: The application bundle. Usually, `Bundle.main`
    ///   - userDefaults: The user defaults object.
    public init(bundle: Bundle, userDefaults: UserDefaults) {
        self.bundle = bundle
        self.userDefaults = userDefaults
    }

    // MARK: - Bundle

    private let bundle: Bundle

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
        bundle.donationsEnabled
    }

    /// When true, it means the app should show an inline donation request UI.
    public var shouldRequestDonations: Bool {
        if !bundle.donationsEnabled { return false }

        if let donationRequestReminderDate = donationRequestReminderDate, donationRequestReminderDate.timeIntervalSinceNow > 0 {
            return false
        }

        return donationRequestDismissedDate == nil
    }
}
