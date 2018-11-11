//
//  RegionsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARegionsModelOperation)
public class RegionsModelOperation: RESTModelOperation {
    public private(set) var regions = [Region]()

    override public func main() {
        super.main()
        regions = decodeModels(type: Region.self)
    }
}

