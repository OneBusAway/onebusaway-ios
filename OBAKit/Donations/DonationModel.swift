//
//  DonationModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/11/23.
//

import SwiftUI
import OBAKitCore

/// `DonationModel` is an `ObservableObject` for use in SwiftUI that manages the donation process.
///
/// It manages the donation data, communicates with the server, and provides updates to the UI.
/// The `DonationModel` class is responsible for handling the donation process, including
/// creating payment intents, presenting the payment sheet, and reporting analytics events.
///
/// Usage:
///     - Create an instance of `DonationModel` with the required dependencies.
///     - Call the `donate(_:recurring:)` method to initiate a donation with a
///       specified amount in cents and recurrence.
///     - Observe the `result` and `donationComplete` properties for updates on the donation process.
///
class DonationModel: ObservableObject {
    let obacoService: ObacoAPIService
    let donationsManager: DonationsManager
    let analytics: Analytics?
    let donationPushNotificationID: String?
    @Published var donationComplete = false

    init(
        obacoService: ObacoAPIService,
        donationsManager: DonationsManager,
        analytics: Analytics?,
        donationPushNotificationID: String?
    ) {
        self.obacoService = obacoService
        self.donationsManager = donationsManager
        self.analytics = analytics
        self.donationPushNotificationID = donationPushNotificationID
    }

    // MARK: - Donation Sheet

    @MainActor
    func donate() {
        donationsManager.dismissDonationsRequests()
        analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donateButtonTapped, value: nil)
        UIApplication.shared.open(URL(string: "https://opentransitsoftwarefoundation.org/donate/")!)
    }
}
