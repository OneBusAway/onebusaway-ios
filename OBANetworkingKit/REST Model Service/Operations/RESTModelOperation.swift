//
//  RESTModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARESTModelOperation)
public class RESTModelOperation: Operation {
    public var apiOperation: RESTAPIOperation?
    public private(set) var references: References?

    required public override init() {
        super.init()
    }

    override public func main() {
        if let references = apiOperation?.references {
            do {
                self.references = try References.decodeReferences(references)
            }
            catch {
                print("Unable to decode references from data: \(error)")
            }
        }
    }
}
