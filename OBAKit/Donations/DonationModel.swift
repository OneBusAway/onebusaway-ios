//
//  DonationModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/11/23.
//

#if canImport(Stripe)
import StripePaymentSheet
import SwiftUI
import OBAKitCore
import PassKit

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
    @Published var result: PaymentSheetResult?
    @Published var paymentSheet: PaymentSheet?
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
    func donate(_ amountInCents: Int, recurring: Bool) async {
        analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donateButtonTapped, value: String(amountInCents))

        let paymentSheet = PaymentSheet(
            intentConfiguration: buildIntentConfiguration(amountInCents, recurring: recurring),
            configuration: buildPaymentSheetConfiguration(amountInCents, recurring: recurring)
        )

        guard let presenter = UIApplication.shared.keyWindowFromScene?.topViewController else {
            fatalError()
        }

        paymentSheet.present(from: presenter) { [weak self] result in
            self?.reportResult(result, amountInCents: amountInCents)
            self?.result = result
            self?.donationComplete = true
        }
    }

    private func reportResult(_ result: PaymentSheetResult, amountInCents: Int) {
        var label: String?
        var value: Any?

        switch result {
        case .completed:
            label = AnalyticsLabels.donationSuccess
            value = String(amountInCents)
        case .failed(let error):
            label = AnalyticsLabels.donationError
            value = error.localizedDescription
        case .canceled: break
        }

        if result == .completed, let donationPushNotificationID {
            analytics?.reportEvent(pageURL: "app://localhost/donations", label: AnalyticsLabels.donationPushNotificationSuccess, value: donationPushNotificationID)
        }

        if let label {
            analytics?.reportEvent(pageURL: "app://localhost/donations", label: label, value: value)
        }
    }

    private func buildIntentConfiguration(_ amountInCents: Int, recurring: Bool) -> PaymentSheet.IntentConfiguration {
        let mode = PaymentSheet.IntentConfiguration.Mode.payment(
            amount: amountInCents,
            currency: "USD",
            setupFutureUsage: recurring ? .offSession : nil
        )

        let intentConfig = PaymentSheet.IntentConfiguration(
            mode: mode
        ) { [weak self] paymentMethod, _, intentCreationCallback in
            let obacoService = self?.obacoService
            let testMode = self?.donationsManager.stripeTestMode ?? true

            Task {
                guard
                    let name = paymentMethod.billingDetails?.name,
                    let email = paymentMethod.billingDetails?.email,
                    let obacoService
                else {
                    intentCreationCallback(.failure(Errors.missingNameOrEmail))
                    return
                }

                do {
                    let intentResponse = try await obacoService.postCreatePaymentIntent(
                        donationAmountInCents: amountInCents,
                        recurring: recurring,
                        name: name,
                        email: email,
                        testMode: testMode
                    )
                    intentCreationCallback(.success(intentResponse.clientSecret))
                } catch let error {
                    intentCreationCallback(.failure(error))
                }
            }
        }
        return intentConfig
    }

    private func buildPaymentSheetConfiguration(_ amountInCents: Int, recurring: Bool) -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()

        configuration.billingDetailsCollectionConfiguration.name = .always
        configuration.billingDetailsCollectionConfiguration.email = .always
        configuration.applePay = buildApplePayConfiguration(amountInCents, recurring: recurring)

        if let extensionURLScheme = Bundle.main.extensionURLScheme {
            configuration.returnURL = "\(extensionURLScheme)://stripe-redirect"
        }

        return configuration
    }

    private func buildApplePayConfiguration(_ amountInCents: Int, recurring: Bool) -> PaymentSheet.ApplePayConfiguration? {
        guard
            let merchantID = Bundle.main.applePayMerchantID,
            let managementURL = Bundle.main.donationManagementPortal
        else {
            return nil
        }

        return PaymentSheet.ApplePayConfiguration(
            merchantId: merchantID,
            merchantCountryCode: "US",
            buttonType: .support,
            customHandlers: recurring ? buildRecurringApplePayConfigurationHandlers(amountInCents, managementURL: managementURL) : buildOneTimeApplePayConfigurationHandlers(amountInCents)
        )
    }

    private func buildOneTimeApplePayConfigurationHandlers(_ amountInCents: Int) -> PaymentSheet.ApplePayConfiguration.Handlers {
        return PaymentSheet.ApplePayConfiguration.Handlers(
            paymentRequestHandler: { request in
                let applePayLabel = OBALoc(
                    "donations.apple_pay.donation_label",
                    value: "OneBusAway Donation",
                    comment: "Required label for Apple Pay for a one-time donation"
                )
                let billing = PKPaymentSummaryItem(
                    label: applePayLabel,
                    amount: NSDecimalNumber(decimal: Decimal(amountInCents) / 100)
                )
                request.paymentSummaryItems = [billing]
                request.requiredShippingContactFields = [.emailAddress, .name]
                return request
            }
        )
    }

    private func buildRecurringApplePayConfigurationHandlers(_ amountInCents: Int, managementURL: URL) -> PaymentSheet.ApplePayConfiguration.Handlers {
        return PaymentSheet.ApplePayConfiguration.Handlers(
            paymentRequestHandler: { request in
                let applePayLabel = OBALoc(
                    "donations.apple_pay.recurring_donation_label",
                    value: "OneBusAway Recurring Donation",
                    comment: "Required label for Apple Pay for a recurring donation"
                )
                let billing = PKRecurringPaymentSummaryItem(
                    label: applePayLabel,
                    amount: NSDecimalNumber(decimal: Decimal(amountInCents) / 100)
                )

                // Payment starts today
                billing.startDate = Date()

                // Pay once a month.
                billing.intervalUnit = .month
                billing.intervalCount = 1

                request.recurringPaymentRequest = PKRecurringPaymentRequest(
                    paymentDescription: applePayLabel,
                    regularBilling: billing,
                    managementURL: managementURL
                )
                request.paymentSummaryItems = [billing]
                request.requiredShippingContactFields = [.emailAddress, .name]
                request.applePayLaterAvailability = .unavailable(.recurringTransaction)

                return request
            }
        )
    }

    // MARK: - Errors

    enum Errors: Error, LocalizedError {
        case missingNameOrEmail

        var errorDescription: String? {
            switch self {
            case .missingNameOrEmail: OBALoc("donation_models.errors.missingNameOrEmail", value: "Donations can only be processed with your name and email", comment: "An error that will be displayed to the user when we lack sufficient data to process their donation.")
            }
        }
    }
}

#else
class DonationModel: ObservableObject {
}
#endif
