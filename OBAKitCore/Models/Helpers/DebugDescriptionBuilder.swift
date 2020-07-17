//
//  DebugDescriptionBuilder.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/**
 A simple way to construct a `debugDescription` property for an object.

 Here's how you might use it:

        public override var debugDescription: String {
            var descriptionBuilder = DebugDescriptionBuilder(baseDescription: super.debugDescription)
            descriptionBuilder.add(key: "id", value: id)
            return descriptionBuilder.description
        }
*/
public struct DebugDescriptionBuilder {
    let baseDescription: String
    var properties = [String: Any]()

    public init(baseDescription: String) {
        self.baseDescription = baseDescription
    }

    public mutating func add(key: String, value: Any?) {
        properties[key] = value ?? "(nil)"
    }

    public var description: String {
        "\(baseDescription) \(properties)"
    }
}
