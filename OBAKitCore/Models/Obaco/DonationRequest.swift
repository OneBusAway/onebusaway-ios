//
//  DonationRequest.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 10/28/23.
//

import Foundation

public struct DonationRequest: Codable, Identifiable, Equatable, Hashable {
    public let id: String
    public let headline: String
    public let body: String
    public let actionButtonText: String
}
