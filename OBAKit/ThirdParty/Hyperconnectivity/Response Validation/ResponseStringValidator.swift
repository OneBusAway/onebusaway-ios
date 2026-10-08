//
//  ResponseStringValidation.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

public class ResponseStringValidator: ResponseValidator {
    
    public enum ValidationMode: Int {
        case containsExpectedResponseString
        case equalsExpectedResponseString
        case matchesRegularExpression
    }
    
    /// The method used to validate the response from the connectivity endpoints.
    public let responseValidationMode: ValidationMode
    
    /// The `String` expected in the response, which is tested based on the validationMode
    public let expectedResponse: String?
    
    /// Initializes the receiver to validate response `String`s
    /// using the given validation mode
    ///
    /// - Parameter validationMode:   The mode to use for validating the response `String`.
    /// - Parameter expectedResponse: The `String` expected in the response, which is
    ///                               tested based on the validationMode
    public init(validationMode: ValidationMode, expectedResponse: String? = nil) {
        self.responseValidationMode = validationMode
        self.expectedResponse = expectedResponse
    }
    
    public func isResponseValid(_ response: URLResponse, data: Data) -> Bool {
        let validator: ResponseValidator
        guard let expectedResponse = self.expectedResponse else {
            switch responseValidationMode {
            case .containsExpectedResponseString:
                validator = ResponseContainsStringValidator()
            case .equalsExpectedResponseString:
                validator = ResponseStringEqualityValidator()
            case .matchesRegularExpression:
                validator = ResponseRegExValidator()
            }
            return validator.isResponseValid(response, data: data)
        }
        switch responseValidationMode {
        case .containsExpectedResponseString:
            validator = ResponseContainsStringValidator(expectedResponse: expectedResponse)
        case .equalsExpectedResponseString:
            validator = ResponseStringEqualityValidator(expectedResponse: expectedResponse)
        case .matchesRegularExpression:
            validator = ResponseRegExValidator(regEx: expectedResponse)
        }
        return validator.isResponseValid(response, data: data)
    }
}
