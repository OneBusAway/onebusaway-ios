//
//  ResponseContainsValidator.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

nonisolated struct ResponseContainsStringValidator: ResponseValidator {

    /// The `String` expected to be contained in the response
    let expectedResponse: String

    /// Initializes the receiver to validate that the response `String` contains the expected response.
    ///
    /// - Parameter expectedResponse: The `String` expected to be contained in the response.
    init(expectedResponse: String = "Success") {
        self.expectedResponse = expectedResponse
    }

    func isResponseValid(_ response: URLResponse, data: Data) -> Bool {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return false
        }
        return responseString.contains(expectedResponse)
    }
}
