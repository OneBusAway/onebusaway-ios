//
//  CodableExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/30/19.
//

import Foundation

extension Decoder {
    /// Convenience accessor for retrieving `References` objects plumbed in via the `userInfo` property.
    var references: References {
        return userInfo[CodingUserInfoKey.references] as! References // swiftlint:disable:this force_cast
    }
}
