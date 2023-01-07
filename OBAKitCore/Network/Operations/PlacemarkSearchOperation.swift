//
//  PlacemarkSearchOperation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit

/// The operation for performing a placemark-search operation.
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
