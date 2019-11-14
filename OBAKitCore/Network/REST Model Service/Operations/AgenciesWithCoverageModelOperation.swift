//
//  AgenciesWithCoverageModelOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/5/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// Creates a `[AgencyWithCoverage]` model response to an API request to the `/api/where/agencies-with-coverage.json` endpoint.
public class AgenciesWithCoverageModelOperation: RESTModelOperation {
    public private(set) var agenciesWithCoverage = [AgencyWithCoverage]()

    /// Performs this class's non-concurrent task.
    ///
    /// - Note: Do not call this method directly. It will be invoked by the `OperationQueue` that manages this operation.
    override public func main() {
        super.main()

        guard !hasError else {
            return
        }

        agenciesWithCoverage = decodeModels(type: AgencyWithCoverage.self)
    }
}
