// PolylineTests.swift
//
// Copyright (c) 2015 Raphaël Mor
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CoreLocation
import Testing

@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable colon mark comma unused_optional_binding

private let COORD_EPSILON: Double = 0.00001

@Suite(.serialized)
final class FunctionalPolylineTests {

    // MARK:- Encoding Coordinates

    @Test func `Empty array should be empty string`() {
        #expect(encodeCoordinates([]) == "")
    }

    @Test func `Zero should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0, longitude: 0)]
        #expect(encodeCoordinates(coordinates) == "??")
    }

    @Test func `Minimal positive difference should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001)]
        #expect(encodeCoordinates(coordinates) == "AA")
    }

    @Test func `Low rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000014, longitude: 0.000014)]
        #expect(encodeCoordinates(coordinates) == "AA")
    }

    @Test func `Mid rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000015, longitude: 0.000015)]
        #expect(encodeCoordinates(coordinates) == "CC")
    }

    @Test func `High rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.000016, longitude: 0.000016)]
        #expect(encodeCoordinates(coordinates) == "CC")
    }

    @Test func `Minimal negative difference should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.00001, longitude: -0.00001)]
        #expect(encodeCoordinates(coordinates) == "@@")
    }

    @Test func `Low negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000014, longitude: -0.000014)]
        #expect(encodeCoordinates(coordinates) == "@@")
    }

    @Test func `Mid negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000015, longitude: -0.000015)]
        #expect(encodeCoordinates(coordinates) == "BB")
    }

    @Test func `High negative rounded values should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: -0.000016, longitude: -0.000016)]
        #expect(encodeCoordinates(coordinates) == "BB")
    }

    @Test func `Small increment location array should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001),
            CLLocationCoordinate2D(latitude: 0.00002, longitude: 0.00002)]
        #expect(encodeCoordinates(coordinates) == "AAAA")
    }

    @Test func `Small decrement location array should be encoded properly`() {
        let coordinates = [CLLocationCoordinate2D(latitude: 0.00001, longitude: 0.00001),
            CLLocationCoordinate2D(latitude: 0.00000, longitude: 0.00000)]
        #expect(encodeCoordinates(coordinates) == "AA@@")
    }

    // MARK: - Decoding Coordinates

    @Test func `Empty polyline should be empty location array`() {
        let coordinates: [CLLocationCoordinate2D] = decodePolyline("")!

        #expect(coordinates.count == 0)
    }

    @Test func `Invalid polyline should return empty location array`() {
        #expect(decodePolyline("invalidPolylineString") as [CLLocationCoordinate2D]? == nil)
    }

    @Test func `Valid polyline should return valid location array`() {
        let coordinates: [CLLocationCoordinate2D] = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")!

        #expect(coordinates.count == 3)
        expectClose(coordinates[0].latitude, 38.5, within: COORD_EPSILON)
        expectClose(coordinates[0].longitude, -120.2, within: COORD_EPSILON)
        expectClose(coordinates[1].latitude, 40.7, within: COORD_EPSILON)
        expectClose(coordinates[1].longitude, -120.95, within: COORD_EPSILON)
        expectClose(coordinates[2].latitude, 43.252, within: COORD_EPSILON)
        expectClose(coordinates[2].longitude, -126.453, within: COORD_EPSILON)
    }

    @Test func `Another valid polyline should return valid location array`() {
        let coordinates: [CLLocationCoordinate2D] = decodePolyline("_ojiHa`tLh{IdCw{Gwc_@")!

        #expect(coordinates.count == 3)
        expectClose(coordinates[0].latitude, 48.8832, within: COORD_EPSILON)
        expectClose(coordinates[0].longitude, 2.23761, within: COORD_EPSILON)
        expectClose(coordinates[1].latitude, 48.82747, within: COORD_EPSILON)
        expectClose(coordinates[1].longitude, 2.23694, within: COORD_EPSILON)
        expectClose(coordinates[2].latitude, 48.87303, within: COORD_EPSILON)
        expectClose(coordinates[2].longitude, 2.40154, within: COORD_EPSILON)
    }

    // MARK:- Encoding levels

    @Test func `Emptylevels should be empty string`() {
        #expect(encodeLevels([]) == "")
    }

    @Test func `Validlevels should be encoded properly`() {
        #expect(encodeLevels([0,1,2,3]) == "?@AB")
    }

    // MARK:- Decoding levels

    @Test func `Empty levels should be empty level array`() {
        if let resultArray = decodeLevels("") {
            #expect(resultArray.count == 0)
        } else {
            Issue.record("Level array should not be nil for empty string")
        }
    }

    @Test func `Invalid levels should return nil level array`() {
        if let _ = decodeLevels("invalidLevelString") {
            Issue.record("Level array should be nil for invalid string")
        } else {
            //Success
        }
    }

    @Test func `Valid levels should return valid level array`() {
        if let resultArray = decodeLevels("?@AB~F") {
            #expect(resultArray.count == 5)
            #expect(resultArray[0] == UInt32(0))
            #expect(resultArray[1] == UInt32(1))
            #expect(resultArray[2] == UInt32(2))
            #expect(resultArray[3] == UInt32(3))
            #expect(resultArray[4] == UInt32(255))

        } else {
            Issue.record("Valid Levels should be decoded properly")
        }
    }

    // MARK: - Encoding Locations
    @Test func `Locations array should be encoded properly`() {
        let locations = [CLLocation(latitude: 0.00001, longitude: 0.00001),
            CLLocation(latitude: 0.00000, longitude: 0.00000)]

        #expect(encodeLocations(locations) == "AA@@")
    }

}
