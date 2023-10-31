//
//  DonationModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/11/23.
//

import StripePaymentSheet
import SwiftUI
import OBAKitCore

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
        let mode = PaymentSheet.IntentConfiguration.Mode.payment(
            amount: amountInCents,
            currency: "USD",
            setupFutureUsage: recurring ? .offSession : nil
        )
        let intentConfig = PaymentSheet.IntentConfiguration(mode: mode) { [weak self] _, _, intentCreationCallback in
            let strongSelf = self
            Task {
                await strongSelf?.handleConfirm(amountInCents, recurring, intentCreationCallback)
            }
        }

        var configuration = PaymentSheet.Configuration()

        configuration.billingDetailsCollectionConfiguration.name = .always
        configuration.billingDetailsCollectionConfiguration.email = .always

        if let extensionURLScheme = Bundle.main.extensionURLScheme {
            configuration.returnURL = "\(extensionURLScheme)://stripe-redirect"
        }

        let paymentSheet = PaymentSheet(intentConfiguration: intentConfig, configuration: configuration)

        guard let presenter = UIApplication.shared.keyWindowFromScene?.topViewController else {
            fatalError()
        }

        paymentSheet.present(from: presenter) { [weak self] result in
            self?.result = result
            self?.donationComplete = true
        }
    }

    func handleConfirm(_ amountInCents: Int, _ recurring: Bool, _ intentCreationCallback: @escaping (Result<String, Error>) -> Void) async {
        do {
            let intent = try await obacoService.postCreatePaymentIntent(donationAmountInCents: amountInCents, recurring: recurring)
            intentCreationCallback(.success(intent.clientSecret))
        } catch let error {
            intentCreationCallback(.failure(error))
        }
    }
}
