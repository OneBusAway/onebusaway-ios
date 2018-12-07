//
//  RegionsModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARegionsModelOperation)
public class RegionsModelOperation: RESTModelOperation {

    /// A list of loaded `Region` objects.
    public private(set) var regions = [Region]()

    /// The raw JSON data downloaded from the server.
    /// Suitable for storing on disk and loading at launch.
    public private(set) var responseData: Data?

    override public func main() {
        super.main()
        responseData = apiOperation?.data
        regions = decodeModels(type: Region.self)
    }
}

