//
//  ResponseRegExValidator.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

public class ResponseRegExValidator: ResponseValidator {
    
    public static let defaultRegularExpression = ".*?<BODY>.*?Success.*?</BODY>.*"
    
    /// Matching options for determining how the response is matched against the regular expression.
    private let options: NSRegularExpression.Options
    
    /// Response `String` is matched against the regex to determine whether or not the response is valid.
    private let regularExpression: String
    
    /// Initializes the receiver to validate the response against a supplied regular expression.
    /// - Parameters:
    ///     - options: Matching options for determining whether or not the response `String`
    ///     matching the provided regular expression.
    ///     - regEx: Regular expression used to validate the response. If the response
    ///     `String` matches the regular expression then the response is deemed to be valid.
    public init(regEx: String = ResponseRegExValidator.defaultRegularExpression,
                options: NSRegularExpression.Options? = nil
    ) {
        self.options = options ?? [.caseInsensitive, .allowCommentsAndWhitespace, .dotMatchesLineSeparators]
        self.regularExpression = regEx
    }
    
    public func isResponseValid(_ response: URLResponse, data: Data) -> Bool {
        guard let responseString = String(data: data, encoding: .utf8),
            let regEx = try? NSRegularExpression(pattern: regularExpression, options: options) else {
                return false
        }
        let responseStrRange = NSRange(location: 0, length: responseString.count)
        let matches = regEx.matches(in: responseString, options: [], range: responseStrRange)
        return !matches.isEmpty
    }
}
