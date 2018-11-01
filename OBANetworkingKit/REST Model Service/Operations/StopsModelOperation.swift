//
//  StopsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/1/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class StopsModelOperation: RESTModelOperation {
    public private(set) var stops: [Stop] = []

    override public func main() {
        super.main()

        guard let entries = apiOperation?.entries else {
            return
        }

        do {
            self.stops = try DictionaryDecoder.decodeModels(entries, type: Stop.self)
        }
        catch {
            print("Unable to decode stops from data: \(error)")
        }
    }
}
