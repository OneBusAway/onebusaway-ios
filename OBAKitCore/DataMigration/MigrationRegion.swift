//
//  MigrationRegion.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 2/22/20.
//

import Foundation

@objc public class MigrationRegion: NSObject, NSCoding {
    public let name: String
    let identifier: Int

    public required init?(coder: NSCoder) {
        guard
            let name = coder.decodeObject(forKey: "regionName") as? String,
            coder.containsValue(forKey: "identifier")
        else {
            return nil
        }

        self.name = name
        self.identifier = coder.decodeInteger(forKey: "identifier")
    }

    public func encode(with coder: NSCoder) { fatalError("This class only supports initialization of an old object. You can't save it back!") }
}
