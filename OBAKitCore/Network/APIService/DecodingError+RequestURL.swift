//
//  DecodingError+RequestURL.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension DecodingError {
    /// The same error, carrying the URL of the request whose response failed to
    /// decode, so `ErrorReport` can name it for support (#1589 follow-up).
    ///
    /// Stays a `DecodingError` with the same case, coding path and description:
    /// callers that match on it, such as a search catching `keyNotFound`, still
    /// match. The URL rides in the userInfo of the context's `underlyingError`:
    /// a copy of the original one, same domain and code (the JSON parser's 3840,
    /// say), or a tag of its own when there was none.
    ///
    /// Done where the response is decoded rather than in `APIService.data(for:)`:
    /// that returns before decoding, so it never sees a `DecodingError`.
    ///
    /// The URL is attached without its query, which holds the API key and
    /// sometimes the rider's coordinates (#1710).
    func withRequestURL(_ url: URL) -> DecodingError {
        let url = ErrorReport.stripQuery(url)
        func tagged(_ context: Context) -> Context {
            let tag: NSError
            if let underlying = context.underlyingError as NSError? {
                var userInfo = underlying.userInfo
                userInfo[NSURLErrorFailingURLErrorKey] = url
                tag = NSError(domain: underlying.domain, code: underlying.code, userInfo: userInfo)
            } else {
                tag = NSError(domain: Self.requestURLErrorDomain, code: 0, userInfo: [NSURLErrorFailingURLErrorKey: url])
            }
            return Context(codingPath: context.codingPath, debugDescription: context.debugDescription, underlyingError: tag)
        }

        switch self {
        case .typeMismatch(let type, let context): return .typeMismatch(type, tagged(context))
        case .valueNotFound(let type, let context): return .valueNotFound(type, tagged(context))
        case .keyNotFound(let key, let context): return .keyNotFound(key, tagged(context))
        case .dataCorrupted(let context): return .dataCorrupted(tagged(context))
        @unknown default: return self
        }
    }

    /// The URL `withRequestURL(_:)` attached, if any.
    var requestURL: URL? {
        let context: Context
        switch self {
        case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found), .dataCorrupted(let found):
            context = found
        @unknown default:
            return nil
        }
        return (context.underlyingError as NSError?)?.userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }

    static let requestURLErrorDomain = "org.onebusaway.DecodingError.requestURL"
}
