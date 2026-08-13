//
//  CountingDataLoader.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Wraps a `MockDataLoader`, counts how many times `data(for:)` is called, and inserts a
/// `Task.yield()` before forwarding so that concurrent tasks genuinely interleave on `@MainActor`.
///
/// Used by ViewModel tests to assert that an in-flight-load guard collapses concurrent calls
/// into a single network request.
// @unchecked Sendable: `callCount` is guarded by `callCountLock`.
class CountingDataLoader: NSObject, URLDataLoader, @unchecked Sendable {
    let inner: MockDataLoader
    private var _callCount = 0
    private let callCountLock = NSLock()
    var callCount: Int { callCountLock.withLock { _callCount } }

    init(_ inner: MockDataLoader) { self.inner = inner }

    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        inner.dataTask(with: request, completionHandler: completionHandler)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCountLock.withLock { _callCount += 1 }
        await Task.yield()
        return try await inner.data(for: request)
    }
}
