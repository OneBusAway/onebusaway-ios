//
//  GTFSRealtimeFeedParserTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftProtobuf
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class GTFSRealtimeFeedParserTests {

    private func makeFeedData(
        timestamp: UInt64? = nil,
        incrementality: TransitRealtime_FeedHeader.Incrementality? = nil,
        entities: [TransitRealtime_FeedEntity] = []
    ) throws -> Data {
        var message = TransitRealtime_FeedMessage()
        message.header.gtfsRealtimeVersion = "2.0"
        if let timestamp {
            message.header.timestamp = timestamp
        }
        if let incrementality {
            message.header.incrementality = incrementality
        }
        message.entity = entities
        return try message.serializedData()
    }

    @Test func `Empty data throws emptyData error`() {
        let parser = GTFSRealtimeFeedParser.standard
        #expect(throws: GTFSRealtimeError.emptyData) {
            try parser.parse(data: Data())
        }
    }

    @Test func `Malformed bytes throw malformedData error`() {
        let parser = GTFSRealtimeFeedParser.standard
        let garbage = Data([0xFF, 0xFE, 0xFD, 0x00, 0x01, 0x02, 0xAA, 0xBB])
        #expect(throws: GTFSRealtimeError.self) {
            try parser.parse(data: garbage)
        }
    }

    @Test func `Valid fullDataset feed message parses successfully`() throws {
        let parser = GTFSRealtimeFeedParser.standard
        var entity = TransitRealtime_FeedEntity()
        entity.id = "V1"
        entity.vehicle = TransitRealtime_VehiclePosition()

        let data = try makeFeedData(timestamp: 1_700_000_000, incrementality: .fullDataset, entities: [entity])
        let message = try parser.parse(data: data)

        #expect(message.header.gtfsRealtimeVersion == "2.0")
        #expect(message.header.timestamp == 1_700_000_000)
        #expect(message.header.incrementality == .fullDataset)
        #expect(message.entity.count == 1)
        #expect(message.entity.first?.id == "V1")
    }

    @Test func `Unsupported differential incrementality is rejected`() throws {
        let parser = GTFSRealtimeFeedParser.standard
        let data = try makeFeedData(incrementality: .differential)

        #expect(throws: GTFSRealtimeError.unsupportedIncrementality(.differential)) {
            try parser.parse(data: data)
        }
    }

    @Test func `Feed header timestamp staleness validation rejects outdated feeds`() throws {
        let parser = GTFSRealtimeFeedParser(maxStaleness: 300) // 5 minutes max staleness
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let staleTimestamp: UInt64 = 1_700_000_000 - 600 // 10 minutes old

        let data = try makeFeedData(timestamp: staleTimestamp)

        do {
            _ = try parser.parse(data: data, referenceDate: referenceDate)
            Issue.record("Expected staleFeed error to be thrown")
        } catch let error as GTFSRealtimeError {
            guard case .staleFeed(let timestamp, let age) = error else {
                Issue.record("Expected .staleFeed, got \(error)")
                return
            }
            #expect(timestamp == Date(timeIntervalSince1970: 1_700_000_000 - 600))
            #expect(age == 600)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `Feed header timestamp too far in future is rejected`() throws {
        let parser = GTFSRealtimeFeedParser(maxFutureTolerance: 120) // 2 minutes max future drift
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let futureTimestamp: UInt64 = 1_700_000_000 + 300 // 5 minutes ahead

        let data = try makeFeedData(timestamp: futureTimestamp)

        do {
            _ = try parser.parse(data: data, referenceDate: referenceDate)
            Issue.record("Expected futureFeed error to be thrown")
        } catch let error as GTFSRealtimeError {
            guard case .futureFeed(let timestamp, let aheadBy) = error else {
                Issue.record("Expected .futureFeed, got \(error)")
                return
            }
            #expect(timestamp == Date(timeIntervalSince1970: 1_700_000_000 + 300))
            #expect(aheadBy == 300)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `Convenience entity extractors filter alert and vehicle types`() throws {
        let parser = GTFSRealtimeFeedParser.standard

        var alertEntity = TransitRealtime_FeedEntity()
        alertEntity.id = "alert_1"
        alertEntity.alert = TransitRealtime_Alert()

        var vehicleEntity = TransitRealtime_FeedEntity()
        vehicleEntity.id = "vehicle_1"
        vehicleEntity.vehicle = TransitRealtime_VehiclePosition()

        var tripEntity = TransitRealtime_FeedEntity()
        tripEntity.id = "trip_1"
        var tripUpdate = TransitRealtime_TripUpdate()
        tripUpdate.trip = TransitRealtime_TripDescriptor()
        tripUpdate.trip.tripID = "trip_id_1"
        tripEntity.tripUpdate = tripUpdate

        let data = try makeFeedData(entities: [alertEntity, vehicleEntity, tripEntity])

        let alerts = try parser.parseAlertEntities(data: data)
        let vehicles = try parser.parseVehicleEntities(data: data)
        let trips = try parser.parseTripUpdateEntities(data: data)

        #expect(alerts.map(\.id) == ["alert_1"])
        #expect(vehicles.map(\.id) == ["vehicle_1"])
        #expect(trips.map(\.id) == ["trip_1"])
    }
}
