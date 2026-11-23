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

    @Test func `Malformed bytes throw malformedData error preserving underlying error`() {
        let parser = GTFSRealtimeFeedParser.standard
        let garbage = Data([0xFF, 0xFE, 0xFD, 0x00, 0x01, 0x02, 0xAA, 0xBB])

        do {
            _ = try parser.parse(data: garbage)
            Issue.record("Expected malformedData error to be thrown")
        } catch let error as GTFSRealtimeError {
            guard case .malformedData(let underlying) = error else {
                Issue.record("Expected .malformedData, got \(error)")
                return
            }
            #expect(underlying is BinaryDecodingError)
        } catch {
            Issue.record("Unexpected error: \(error)")
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

    @Test func `Standard parser accepts future feed without rejecting on clock skew`() throws {
        let parser = GTFSRealtimeFeedParser.standard
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let futureTimestamp: UInt64 = 1_700_000_000 + 3600 // 1 hour in the future

        let data = try makeFeedData(timestamp: futureTimestamp, incrementality: .fullDataset)
        let message = try parser.parse(data: data, referenceDate: referenceDate)

        #expect(message.header.timestamp == futureTimestamp)
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

    @Test func `Opt-in future tolerance rejects feeds exceeding threshold`() throws {
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

    @Test func `Error description formats durations without integer overflow trap`() {
        let testDate = Date(timeIntervalSince1970: 1_700_000_000)

        // Standard values
        let stale = GTFSRealtimeError.staleFeed(timestamp: testDate, age: 300)
        #expect(stale.errorDescription?.contains("300s") == true)

        let future = GTFSRealtimeError.futureFeed(timestamp: testDate, aheadBy: 120)
        #expect(future.errorDescription?.contains("120s") == true)

        // Extreme values that would overflow Int on 32-bit watchOS or trap in Int(Double)
        let hugeStale = GTFSRealtimeError.staleFeed(timestamp: testDate, age: Double.greatestFiniteMagnitude)
        #expect(hugeStale.errorDescription != nil)

        let infiniteFuture = GTFSRealtimeError.futureFeed(timestamp: testDate, aheadBy: Double.infinity)
        #expect(infiniteFuture.errorDescription != nil)

        let empty = GTFSRealtimeError.emptyData
        #expect(empty.errorDescription != nil)

        let unsupported = GTFSRealtimeError.unsupportedIncrementality(.differential)
        #expect(unsupported.errorDescription != nil)
    }

    // MARK: - Edge Cases & Equatable Conformance

    @Test func `Feed header without timestamp bypasses staleness and future checks`() throws {
        let parser = GTFSRealtimeFeedParser(maxStaleness: 10, maxFutureTolerance: 10)
        let data = try makeFeedData(timestamp: nil, incrementality: .fullDataset)
        let message = try parser.parse(data: data)
        #expect(!message.header.hasTimestamp)
    }

    @Test func `Feed header with zero timestamp bypasses staleness and future checks`() throws {
        let parser = GTFSRealtimeFeedParser(maxStaleness: 10, maxFutureTolerance: 10)
        let data = try makeFeedData(timestamp: 0, incrementality: .fullDataset)
        let message = try parser.parse(data: data)
        #expect(message.header.timestamp == 0)
    }

    @Test func `Feed header with custom allowed incrementality permits differential feeds`() throws {
        let customParser = GTFSRealtimeFeedParser(allowedIncrementalities: [.differential, .fullDataset])
        let data = try makeFeedData(incrementality: .differential)
        let message = try customParser.parse(data: data)
        #expect(message.header.incrementality == .differential)
    }

    @Test func `Feed header with exact staleness boundary is accepted`() throws {
        let parser = GTFSRealtimeFeedParser(maxStaleness: 300)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_300)
        let exactTimestamp: UInt64 = 1_700_000_000

        let data = try makeFeedData(timestamp: exactTimestamp)
        let message = try parser.parse(data: data, referenceDate: referenceDate)
        #expect(message.header.timestamp == exactTimestamp)
    }

    @Test func `Feed header with exact future tolerance boundary is accepted`() throws {
        let parser = GTFSRealtimeFeedParser(maxFutureTolerance: 120)
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let exactFutureTimestamp: UInt64 = 1_700_000_120

        let data = try makeFeedData(timestamp: exactFutureTimestamp)
        let message = try parser.parse(data: data, referenceDate: referenceDate)
        #expect(message.header.timestamp == exactFutureTimestamp)
    }

    @Test func `GTFSRealtimeError Equatable conformance distinguishes error variants and attributes`() {
        let date1 = Date(timeIntervalSince1970: 1_000)
        let date2 = Date(timeIntervalSince1970: 2_000)

        #expect(GTFSRealtimeError.emptyData == GTFSRealtimeError.emptyData)
        #expect(GTFSRealtimeError.emptyData != GTFSRealtimeError.unsupportedIncrementality(.differential))

        #expect(
            GTFSRealtimeError.unsupportedIncrementality(.differential)
            == GTFSRealtimeError.unsupportedIncrementality(.differential)
        )
        #expect(
            GTFSRealtimeError.unsupportedIncrementality(.differential)
            != GTFSRealtimeError.unsupportedIncrementality(.fullDataset)
        )

        #expect(
            GTFSRealtimeError.staleFeed(timestamp: date1, age: 100)
            == GTFSRealtimeError.staleFeed(timestamp: date1, age: 100)
        )
        #expect(
            GTFSRealtimeError.staleFeed(timestamp: date1, age: 100)
            != GTFSRealtimeError.staleFeed(timestamp: date2, age: 100)
        )
        #expect(
            GTFSRealtimeError.staleFeed(timestamp: date1, age: 100)
            != GTFSRealtimeError.staleFeed(timestamp: date1, age: 200)
        )

        #expect(
            GTFSRealtimeError.futureFeed(timestamp: date1, aheadBy: 50)
            == GTFSRealtimeError.futureFeed(timestamp: date1, aheadBy: 50)
        )
        #expect(
            GTFSRealtimeError.futureFeed(timestamp: date1, aheadBy: 50)
            != GTFSRealtimeError.futureFeed(timestamp: date2, aheadBy: 50)
        )
        #expect(
            GTFSRealtimeError.futureFeed(timestamp: date1, aheadBy: 50)
            != GTFSRealtimeError.futureFeed(timestamp: date1, aheadBy: 150)
        )

        enum CustomTestError: Error, Sendable {
            case a, b
        }
        #expect(GTFSRealtimeError.malformedData(CustomTestError.a) == GTFSRealtimeError.malformedData(CustomTestError.a))
        #expect(GTFSRealtimeError.malformedData(CustomTestError.a) != GTFSRealtimeError.malformedData(CustomTestError.b))
        #expect(GTFSRealtimeError.malformedData(CustomTestError.a) != GTFSRealtimeError.emptyData)
    }
}
