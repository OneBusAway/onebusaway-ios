//
//  VehicleProblemViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// What the vehicle problem form sends when the rider taps Send Message, and
/// what happens after. The form's `submit()` hands its fields to
/// `VehicleProblemView.submit`, which these tests call directly: hosted
/// SwiftUI controls can't be driven in the test host.
@MainActor
@Suite(.serialized)
struct VehicleProblemViewTests {

    private struct SendFailure: Error {}

    /// What the form sent, and how many times it said the report was sent.
    private final class Recorder {
        var sent: [VehicleProblemInput] = []
        var sentCount = 0
        /// `sentCount` as it was while the send was still running.
        var sentCountDuringSend: Int?
    }

    private func submit(
        code: TripProblemCode = .neverCame,
        isOnVehicle: Bool = false,
        vehicleID: String = "",
        comment: String = "",
        shareLocation: Bool = true,
        recorder: Recorder,
        failing: Bool = false
    ) async -> Error? {
        await VehicleProblemView.submit(
            code: code,
            isOnVehicle: isOnVehicle,
            vehicleID: vehicleID,
            comment: comment,
            shareLocation: shareLocation,
            send: { input in
                recorder.sent.append(input)
                recorder.sentCountDuringSend = recorder.sentCount
                if failing { throw SendFailure() }
            },
            onSent: { recorder.sentCount += 1 }
        )
    }

    /// Every value differs from the form's default, and the two switches differ
    /// from each other, so a field dropped or crossed with another fails.
    @Test func `The report carries the problem, the on-vehicle answer and the location choice`() async throws {
        let recorder = Recorder()

        let error = await submit(code: .wrongHeadsign, isOnVehicle: true, vehicleID: "1_8198", comment: "Sign said Downtown", shareLocation: false, recorder: recorder)

        #expect(error == nil)
        #expect(recorder.sent.count == 1)
        let input = try #require(recorder.sent.first)
        #expect(input.code == .wrongHeadsign)
        #expect(input.isOnVehicle)
        #expect(!input.shareLocation)
        #expect(input.vehicleID == "1_8198")
        #expect(input.comment == "Sign said Downtown")
    }

    /// The server treats an empty value differently from a missing one.
    @Test func `A blank vehicle ID and comment are sent as missing`() async throws {
        let recorder = Recorder()

        _ = await submit(vehicleID: "   ", comment: " \n ", recorder: recorder)

        let input = try #require(recorder.sent.first)
        #expect(input.vehicleID == nil)
        #expect(input.comment == nil)
    }

    @Test func `The vehicle ID and comment are sent without surrounding spaces`() async throws {
        let recorder = Recorder()

        _ = await submit(vehicleID: " 1_8198 ", comment: "  Came 10 minutes early\n", recorder: recorder)

        let input = try #require(recorder.sent.first)
        #expect(input.vehicleID == "1_8198")
        #expect(input.comment == "Came 10 minutes early")
    }

    /// `onSent` closes the form, so it must wait for the send to finish.
    @Test func `The form closes only after the report is sent`() async {
        let recorder = Recorder()

        let error = await submit(recorder: recorder)

        #expect(error == nil)
        #expect(recorder.sentCountDuringSend == 0)
        #expect(recorder.sentCount == 1)
    }

    /// The view shows the returned error and keeps the rider's input.
    @Test func `A failed send returns its error and keeps the form open`() async {
        let recorder = Recorder()

        let error = await submit(recorder: recorder, failing: true)

        #expect(error is SendFailure)
        #expect(recorder.sent.count == 1)
        #expect(recorder.sentCount == 0)
    }
}
