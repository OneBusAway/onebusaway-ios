//
//  RegionsModelService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Downloads and transforms data into `Region` model objects.
public class RegionsModelService: ModelService {
    private let apiService: RegionsAPIService

    /// Creates a `RegionsModelService` object.
    ///
    /// - Parameters:
    ///   - apiService: The API service that will provide data to the model service.
    ///   - dataQueue: An operation queue that will service requests for this object.
    public init(apiService: RegionsAPIService, dataQueue: OperationQueue) {
        self.apiService = apiService
        super.init(dataQueue: dataQueue)
    }

    /// Creates the API request and model transformation operations necessary to retrieve `Region`s.
    ///
    /// - Returns: An operation from which regions can be retrieved after the operation completes.
    public func getRegions() -> RegionsModelOperation {
        let service = apiService.getRegions()
        let data = RegionsModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }
        return data
    }
}
