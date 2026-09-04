//
//  GhostBusReport.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Everything the app knows about the trip the rider says never showed up.
/// Fields mirror the sidecar's ghost_bus_reports create params; timestamps go
/// over the wire as epoch milliseconds.
public struct GhostBusReportDraft {
    public var tripID: String
    public var serviceDate: Date
    public var routeID: String?
    public var stopID: StopID?
    public var vehicleID: String?
    public var stopSequence: Int?
    public var predicted: Bool?
    public var scheduledArrivalAt: Date?
    public var predictedArrivalAt: Date?
    public var scheduleDeviationMinutes: Int?
    public var predictionLastUpdatedAt: Date?
    public var waitDurationMinutes: Int
    public var comment: String?
    public var userLatitude: Double?
    public var userLongitude: Double?

    public init(tripID: String, serviceDate: Date, waitDurationMinutes: Int = 15) {
        self.tripID = tripID
        self.serviceDate = serviceDate
        self.waitDurationMinutes = waitDurationMinutes
    }
}

/// The sidecar's acknowledgement of a submitted ghost bus report.
public struct GhostBusReport: Codable {
    /// Server-generated public identifier for the report.
    public let id: String
}
