//
//  ScheduleFetchError.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Cancellation from `.task(id:)` / `URLSession`. Must not become the
/// schedule sheet's visible error, and must not clear a newer fetch's spinner.
enum ScheduleFetchError {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
