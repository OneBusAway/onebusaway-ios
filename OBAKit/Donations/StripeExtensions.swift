//
//  StripeExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/16/24.
//

#if canImport(Stripe)
import StripePaymentSheet

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
#endif
