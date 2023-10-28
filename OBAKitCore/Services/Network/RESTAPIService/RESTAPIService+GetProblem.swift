//
//  RESTAPIService+GetProblem.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/30/22.
//

import CoreLocation

extension RESTAPIService {
    // MARK: - Stop problem reporting
    public struct StopProblemReport {
        /// The stop ID where the problem was encountered.
        public var stopID: StopID

        /// A code to indicate the type of problem encountered.
        public var code: StopProblemCode

        /// An optional free text field that allows the user to provide more context.
        public var comment: String?

        /// An optional location value to provide more context.
        public var location: CLLocation?

        public init(stopID: StopID, code: StopProblemCode, comment: String? = nil, location: CLLocation? = nil) {
            self.stopID = stopID
            self.code = code
            self.comment = comment
            self.location = location
        }
    }

    /// Submit a user-generated problem report for a particular stop.
    ///
    /// - API Endpoint: `/api/where/report-problem-with-stop/{stopID}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/1.1.19/api/where/methods/report-problem-with-stop.html)
    ///
    /// The reporting mechanism provides lots of fields that can be specified to give more context
    /// about the details of the problem (which trip, stop, vehicle, etc was involved), making it
    /// easier for a developer or transit agency staff to diagnose the problem. These reports feed
    /// into the problem reporting admin interface.
    ///
    /// - parameter report: The problem report to submit.
    /// - throws: ``APIError`` or other errors.
    /// - returns: ``CoreRESTAPIResponse``.
    public nonisolated func getStopProblem(report: StopProblemReport) async throws -> CoreRESTAPIResponse {
        let url = urlBuilder.getStopProblem(stopID: report.stopID, code: report.code, comment: report.comment, location: report.location)
        return try await getData(for: url, decodeAs: CoreRESTAPIResponse.self)
    }

    // MARK: - Trip problem reporting
    /// A problem report for a particular trip. Use with ``getTripProblem(report:)`` to submit a report.
    public struct TripProblemReport {
        // @ualch9: maybe we can adopt this struct for parameters everywhere?
        //          that would be replacing urlBuilder with a `URLBuilder` protocol.

        /// The trip ID on which the problem was encountered.
        public var tripID: String

        /// The service date of the trip.
        public var serviceDate: Date

        /// The vehicle ID on which the problem was encountered.
        public var vehicleID: String?

        /// The stop ID indicating the stop where the problem was encountered.
        public var stopID: StopID?

        /// An identifier clarifying the type of problem encountered.
        public var code: TripProblemCode

        /// Free-form user input describing the issue.
        public var comment: String?

        /// Indicates if the user is on the vehicle experiencing the issue.
        public var userOnVehicle: Bool

        /// The user's current location.
        public var location: CLLocation?

        public init(tripID: String, serviceDate: Date, vehicleID: String? = nil, stopID: StopID? = nil, code: TripProblemCode, comment: String? = nil, userOnVehicle: Bool, location: CLLocation? = nil) {
            self.tripID = tripID
            self.serviceDate = serviceDate
            self.vehicleID = vehicleID
            self.stopID = stopID
            self.code = code
            self.comment = comment
            self.userOnVehicle = userOnVehicle
            self.location = location
        }
    }

    /// Submit a user-generated problem report for a particular trip.
    ///
    /// - API Endpoint: `/api/where/report-problem-with-trip/{stopID}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/1.1.19/api/where/methods/report-problem-with-trip.html)
    ///
    /// The reporting mechanism provides lots of fields that can be specified to give more context about the details of the
    /// problem (which trip, stop, vehicle, etc was involved), making it easier for a developer or transit agency staff to
    /// diagnose the problem. These reports feed into the problem reporting admin interface.
    ///
    /// - parameter report: The problem report to submit.
    /// - throws: ``APIError`` or other errors.
    /// - returns: ``CoreRESTAPIResponse``.
    public nonisolated func getTripProblem(report: TripProblemReport) async throws -> CoreRESTAPIResponse {
        let url = urlBuilder.getTripProblem(tripID: report.tripID, serviceDate: report.serviceDate, vehicleID: report.vehicleID, stopID: report.stopID, code: report.code, comment: report.comment, userOnVehicle: report.userOnVehicle, location: report.location)
        return try await getData(for: url, decodeAs: CoreRESTAPIResponse.self)
    }
}
