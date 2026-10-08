//
//  ResponseRegExValidator.swift
//  Hyperconnectivity
//
//  Created by Ross Butler on 08/05/2020.
//

import Foundation

nonisolated struct ResponseRegExValidator: ResponseValidator {

    static let defaultRegularExpression = ".*?<BODY>.*?Success.*?</BODY>.*"

    /// Matching options for determining how the response is matched against the regular expression.
    private let options: NSRegularExpression.Options

    /// Response `String` is matched against the regex to determine whether or not the response is valid.
    private let regularExpression: String

    /// Initializes the receiver to validate the response against a supplied regular expression.
    /// - Parameters:
    ///     - regEx: Regular expression used to validate the response. If the response
    ///     `String` matches the regular expression then the response is deemed to be valid.
    ///     - options: Matching options for determining whether or not the response `String`
    ///     matching the provided regular expression.
    init(regEx: String = ResponseRegExValidator.defaultRegularExpression,
         options: NSRegularExpression.Options? = nil
    ) {
        self.options = options ?? [.caseInsensitive, .allowCommentsAndWhitespace, .dotMatchesLineSeparators]
        self.regularExpression = regEx
    }

    func isResponseValid(_ response: URLResponse, data: Data) -> Bool {
        guard let responseString = String(data: data, encoding: .utf8),
            let regEx = try? NSRegularExpression(pattern: regularExpression, options: options) else {
                return false
        }
        // OBA: upstream sized the range in Characters, but NSRange counts UTF-16
        // units, so any non-ASCII response was only partly searched.
        let responseStrRange = NSRange(responseString.startIndex..., in: responseString)
        return regEx.firstMatch(in: responseString, options: [], range: responseStrRange) != nil
    }
}
