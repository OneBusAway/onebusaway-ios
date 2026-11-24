//
//  SavedArrivalsStore.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The last arrivals response and the day's timetable for each stop, kept on
/// disk so the bookmark screens have something to show when the device is
/// offline.
///
/// One file per stop and kind, holding the response body as the server sent
/// it, under a folder per region: a body only decodes against its own region's
/// service. The file's modification date is when it was saved. It lives in
/// Caches, so the system may purge it; that only costs the offline fallback.
public struct SavedArrivalsStore: Sendable {
    /// What a saved body is.
    public enum Kind: Sendable {
        /// An `arrivals-and-departures-for-stop` response: real-time
        /// departures for about the next hour.
        case arrivals

        /// A `schedule-for-stop` response: the stop's timetable for a day.
        case schedule

        var fileSuffix: String {
            switch self {
            case .arrivals: return ".json"
            case .schedule: return ".schedule.json"
            }
        }
    }

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's store, in its Caches directory.
    public static let appDefault = SavedArrivalsStore(
        directory: URL.cachesDirectory.appending(path: "SavedArrivals", directoryHint: .isDirectory)
    )

    /// Saves `body` as `stopID`'s latest response of `kind`, replacing any
    /// earlier one. Failures are logged: losing a save only costs the offline
    /// fallback.
    public func save(_ body: Data, kind: Kind = .arrivals, stopID: StopID, regionID: Int, savedAt: Date = Date()) {
        let url = fileURL(kind: kind, stopID: stopID, regionID: regionID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: savedAt], ofItemAtPath: url.path)
        } catch {
            Logger.error("SavedArrivalsStore: saving \(kind) for stop \(stopID) failed: \(error.localizedDescription)")
        }
    }

    /// `stopID`'s saved body of `kind` and when it was saved, or `nil` if none.
    public func load(kind: Kind = .arrivals, stopID: StopID, regionID: Int) -> (body: Data, savedAt: Date)? {
        let url = fileURL(kind: kind, stopID: stopID, regionID: regionID)
        guard
            let body = try? Data(contentsOf: url),
            let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else {
            return nil
        }
        return (body, savedAt)
    }

    /// Stop IDs are agency-prefixed strings ("1_75414") that may carry
    /// characters a file name can't, so they are percent-encoded.
    func fileURL(kind: Kind = .arrivals, stopID: StopID, regionID: Int) -> URL {
        let name = stopID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? stopID
        return directory
            .appending(path: String(regionID), directoryHint: .isDirectory)
            .appending(path: name + kind.fileSuffix, directoryHint: .notDirectory)
    }
}

/// A stop's arrivals fetch failed because the device couldn't reach the
/// server, and what was saved for the stop stands in for it: the last
/// real-time departures, and the day's timetable for when those run out.
///
/// Delivered as the failure of the fetch, which it is, so a caller that knows
/// nothing about saved arrivals still treats it as one.
public struct SavedArrivalsFallback: Error {
    /// The saved departures that haven't left yet, as they were when saved.
    public let arrivals: [ArrivalDeparture]

    /// When the real-time departures were saved, or, with none saved, the
    /// timetable.
    public let savedAt: Date

    /// The stop's timetable departures that haven't left yet. Empty when no
    /// timetable was saved.
    public let scheduledDepartures: [ScheduledDeparture]

    /// Why the fetch failed.
    public let underlyingError: Error
}
