//
//  DonationModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/11/23.
//

import StripePaymentSheet
import SwiftUI
import OBAKitCore
import PassKit

extension PaymentSheetResult: Equatable {
    public static func == (lhs: PaymentSheetResult, rhs: PaymentSheetResult) -> Bool {
        switch (lhs, rhs) {
        case (.completed, .completed), (.canceled, .canceled):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

class DonationModel: ObservableObject {
    let obacoService: ObacoAPIService
    let analytics: Analytics?
    @Published var result: PaymentSheetResult?
    @Published var paymentSheet: PaymentSheet?
    @Published var donationComplete = false

    init(obacoService: ObacoAPIService, analytics: Analytics?) {
        self.obacoService = obacoService
        self.analytics = analytics
    }

    @MainActor
    func donate(_ amountInCents: Int, recurring: Bool) async {
        analytics?.reportEvent?(.userAction, label: AnalyticsLabels.donateButtonTapped, value: String(amountInCents))

        let paymentSheet = PaymentSheet(
            intentConfiguration: buildIntentConfiguration(amountInCents, recurring: recurring),
            configuration: buildPaymentSheetConfiguration(amountInCents, recurring: recurring)
        )

        guard let presenter = UIApplication.shared.keyWindowFromScene?.topViewController else {
            fatalError()
        }

        paymentSheet.present(from: presenter) { [weak self] result in
            self?.result = result
            self?.donationComplete = true
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
            let strongSelf = self
            Task {
                await strongSelf?.handleConfirm(amountInCents, recurring, intentCreationCallback)
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
                request.requiredShippingContactFields = [.emailAddress]
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
                request.requiredShippingContactFields = [.emailAddress]

                if #available(iOS 17.0, *) {
                    request.applePayLaterAvailability = .unavailable(.recurringTransaction)
                }

                return request
            }
        )
    }

    private func handleConfirm(_ amountInCents: Int, _ recurring: Bool, _ intentCreationCallback: @escaping (Result<String, Error>) -> Void) async {
        do {
            let intent = try await obacoService.postCreatePaymentIntent(donationAmountInCents: amountInCents, recurring: recurring, testMode: false) // abxoxo TODO
            intentCreationCallback(.success(intent.clientSecret))
        } catch let error {
            intentCreationCallback(.failure(error))
        }
    }
}
