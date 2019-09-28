//
//  PlacemarkSearchOperation.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

/// The operation for performing a placemark-search operation.
///
/// - Note: this operation uses `MKLocalSearch` under the hood, which is why it inherits from `AsyncOperation`
///         instead of `NetworkOperation`.
public class PlacemarkSearchOperation: AsyncOperation {

    public let request: MKLocalSearch.Request
    private var localSearch: MKLocalSearch?
    public private(set) var response: MKLocalSearch.Response?

    public init(query: String, region: MKCoordinateRegion) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        self.request = request
    }

    public override func start() {
        super.start()

        let search = MKLocalSearch(request: request)

        search.start { [weak self] (response, error) in
            guard
                let self = self,
                !self.isCancelled
            else { return }

            self.error = error
            self.response = response
            self.finish()
        }

        self.localSearch = search
    }

    public override func cancel() {
        super.cancel()
        localSearch?.cancel()
        finish()
    }
}
