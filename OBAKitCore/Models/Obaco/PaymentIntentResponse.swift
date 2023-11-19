//
//  PaymentIntentResponse.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 11/11/23.
//

import Foundation

public struct PaymentIntentResponse: Codable, Identifiable, Equatable, Hashable {
    public var clientSecret: String
    public var customerID: String?
    public var ephemeralKey: String?
    public var id: String

    private enum CodingKeys: String, CodingKey {
        case clientSecret = "client_secret"
        case customerID = "customer_id"
        case ephemeralKey = "ephemeral_key"
        case id = "id"
    }
}
