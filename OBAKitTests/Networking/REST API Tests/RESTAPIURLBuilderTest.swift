//
//  RESTAPIURLBuilderTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 12/24/19.
//

import XCTest
import Nimble
@testable import OBAKitCore

class RESTAPIURLBuilderTest: OBATestCase {

    func testDefaultQueryParams() {
        let queryItem = URLQueryItem(name: "key", value: "org.onebusaway.iphone")
        let builder = RESTAPIURLBuilder(baseURL: URL(string: "https://www.example.com")!, defaultQueryItems: [queryItem])
        let url = builder.generateURL(path: "path.json")
        expect(url.absoluteString) == "https://www.example.com/path.json?key=org.onebusaway.iphone"
    }

    func testAppendedQueryParams() {
        let builder = RESTAPIURLBuilder(baseURL: URL(string: "https://www.example.com")!, defaultQueryItems: [])
        let url = builder.generateURL(path: "path.json", params: ["key": "org.onebusaway.iphone"])
        expect(url.absoluteString) == "https://www.example.com/path.json?key=org.onebusaway.iphone"
    }

    func testHappyPath() {
        let queryItem = URLQueryItem(name: "key", value: "org.onebusaway.iphone")
        let builder = RESTAPIURLBuilder(baseURL: URL(string: "https://www.example.com")!, defaultQueryItems: [queryItem])
        let url = builder.generateURL(path: "path.json", params: ["minutesBefore": "5"])

        let optionOne = url.absoluteString == "https://www.example.com/path.json?key=org.onebusaway.iphone&minutesBefore=5"
        let optionTwo = url.absoluteString == "https://www.example.com/path.json?minutesBefore=5&key=org.onebusaway.iphone"

        XCTAssertTrue(optionOne || optionTwo)
    }

    func testRealWorldCase() {
        let builder = RESTAPIURLBuilder(baseURL: URL(string: "http://api.tampa.onebusaway.org/api/")!, defaultQueryItems: [URLQueryItem(name: "foo", value: "bar")])
        let url = builder.generateURL(path: "/api/where/arrivals-and-departures-for-stop/Hillsborough%20Area%20Regional%20Transit_4543.json")

        expect(url.absoluteString) == "http://api.tampa.onebusaway.org/api/api/where/arrivals-and-departures-for-stop/Hillsborough%20Area%20Regional%20Transit_4543.json?foo=bar"
    }
}
