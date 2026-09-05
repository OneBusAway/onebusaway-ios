//
//  APIError+MissingStop.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public extension APIError {

    /// Whether this error means the server has no stop at the requested ID,
    /// rather than that the request failed.
    ///
    /// Two transport shapes carry that meaning, and a caller that checks only one
    /// of them disagrees with the surfaces that check the other (#1336):
    ///
    /// - A literal HTTP 404.
    /// - HTTP 200 with the body `null`, which many OBA servers send instead of a
    ///   404. `APIService+GetData` throws it as
    ///   `invalidContentType(_, "json", "nothing")` — the shape in #1331.
    ///
    /// An empty HTTP 200 is deliberately excluded even though `APIService+GetData`
    /// also throws that as `requestNotFound`: a live stop answers with a full 200
    /// (traced against realtime.sdmts.com on 2026-08-14), so a blank body is a
    /// transient blip rather than a missing stop. `ErrorClassifier` reclassifies it
    /// as `.invalidResponseData` so the rider isn't told "404 Not found" about a
    /// response that was a 200.
    var indicatesMissingStop: Bool {
        switch self {
        case .requestNotFound(let response) where response.statusCode == 404:
            return true
        case .invalidContentType(_, let expected, let actual)
            where expected == "json" && actual == "nothing":
            return true
        default:
            return false
        }
    }
}
