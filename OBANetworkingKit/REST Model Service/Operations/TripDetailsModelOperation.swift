//
//  TripDetailsModelOperation.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/27/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBATripDetailsModelOperation)
public class TripDetailsModelOperation: RESTModelOperation {
    public private(set) var tripDetails: TripDetails?

    override public func main() {
        super.main()

        guard let entry = apiOperation?.entries?.first else {
            return
        }

        do {
            self.tripDetails = try DictionaryDecoder.decodeModel(entry, type: TripDetails.self)
        }
        catch {
            print("Unable to decode trip details from data: \(error)")
        }
    }
}
