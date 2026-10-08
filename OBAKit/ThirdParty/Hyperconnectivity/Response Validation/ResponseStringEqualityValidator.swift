//
//  ResponseStringEqualityValidator.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

public class ResponseStringEqualityValidator: ResponseValidator {
    
    /// The `String` expected as the response
    public let expectedResponse: String

    /// Initializes the receiver to validate that the response `String` is equal to the expected response.
    ///
    /// - Parameter expectedResponse: The `String` expected as the response.
    public init(expectedResponse: String = "Success") {
        self.expectedResponse = expectedResponse
    }

    public func isResponseValid(_ response: URLResponse, data: Data) -> Bool {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return false
        }
        return expectedResponse == responseString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
