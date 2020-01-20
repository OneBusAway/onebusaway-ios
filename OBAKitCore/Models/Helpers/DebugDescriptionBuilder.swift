//
//  DebugDescriptionBuilder.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 1/16/20.
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
