//
//  ScheduleContentState.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// What a schedule screen shows: a spinner, the error, its content, or its
/// empty message. The stop and route schedule views both decide this the same
/// way, and keeping the order of the checks here lets tests reach it.
enum ScheduleContentState {
    case loading
    case failed(Error)
    case content
    case empty

    /// - Parameters:
    ///   - isLoading: Whether a load is in flight.
    ///   - hasContent: Whether there is anything to show. A reload keeps
    ///     showing it rather than the spinner.
    ///   - error: The last load's error, which wins over stale content.
    init(isLoading: Bool, hasContent: Bool, error: Error?) {
        if isLoading && !hasContent {
            self = .loading
        } else if let error {
            self = .failed(error)
        } else if hasContent {
            self = .content
        } else {
            self = .empty
        }
    }
}

/// Identity for a schedule fetch: the selected date and the formatter time
/// zone generation. Both schedule views use it as their `.task(id:)`
/// identity, so a zone change refetches the schedule in the new zone (#1978).
///
/// A named struct rather than a `(Date, Int)` tuple: tuples cannot satisfy
/// the `Equatable` requirement of `.task(id:)` in Swift 6.2.
struct ScheduleFetchIdentity: Equatable {
    var selectedDate: Date
    var formattersTimeZoneGeneration: Int
}
