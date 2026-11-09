//
//  StopsForAgencyTests.swift
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

@Suite(.serialized)
final class StopsForAgencyTests: OBATestCase {
    private var dataLoader: MockDataLoader!
    private var service: RESTAPIService!

    override init() async throws {
        try await super.init()
        dataLoader = MockDataLoader(testName: name)
        service = buildRESTService(dataLoader: dataLoader)
    }

    /// Stubs `path` with `data`, adding `headers` to the response, and records
    /// the request that matched.
    private func mock(path: String, data: Data, statusCode: Int = 200, contentType: String = "application/json", headers: [String: String] = [:]) -> SendableBox<URLRequest?> {
        let captured = SendableBox<URLRequest?>(nil)
        var fields = ["Content-Type": contentType, "Content-Length": String(data.count)]
        fields.merge(headers) { _, new in new }
        let response = HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: "2", headerFields: fields)
        dataLoader.mock(response: MockDataResponse(data: data, urlResponse: response, error: nil) { request in
            guard request.url?.path.contains(path) ?? false else { return false }
            captured.value = request
            return true
        })
        return captured
    }

    private func response(_ statusCode: Int, _ contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: "2", headerFields: ["Content-Type": contentType])!
    }

    @Test func `Stops for an agency arrive with their routes, region and ETag`() async throws {
        _ = mock(path: "/api/where/stops-for-agency/1.json", data: Fixtures.loadData(file: "stops-for-agency-tampa-1.json"), headers: ["ETag": "3f9a"])

        let result = try await service.getStopsForAgency(id: "1")

        guard case let .stops(stops, etag) = result else {
            Issue.record("Expected stops, got \(result)")
            return
        }
        #expect(stops.map(\.id) == ["1_1013", "1_1014", "1_1015"])
        #expect(stops.map(\.code) == ["1013", "1014", "1015"])
        #expect(stops.first?.routes.map(\.shortName) == ["45"])
        #expect(stops.first?.regionIdentifier == pugetSoundRegionIdentifier)
        #expect(etag == "3f9a")
    }

    /// A region can be megabytes: it must not download on Low Data Mode, must
    /// outlast the usual 10 s timeout, and must reach the server so a 304 is real.
    @Test func `The request skips Low Data Mode and the cache, and sends the ETag only when given`() async throws {
        let fixture = Fixtures.loadData(file: "stops-for-agency-tampa-1.json")
        let plain = mock(path: "/api/where/stops-for-agency/1.json", data: fixture)
        _ = try await service.getStopsForAgency(id: "1")

        let request = try #require(plain.value)
        #expect(request.allowsConstrainedNetworkAccess == false)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == 60)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)

        let conditional = mock(path: "/api/where/stops-for-agency/2.json", data: fixture)
        _ = try await service.getStopsForAgency(id: "2", ifNoneMatch: "3f9a")
        #expect(conditional.value?.value(forHTTPHeaderField: "If-None-Match") == "3f9a")
    }

    @Test func `A 304 means nothing changed`() async throws {
        _ = mock(path: "/api/where/stops-for-agency/1.json", data: Data(), statusCode: 304)

        let result = try await service.getStopsForAgency(id: "1", ifNoneMatch: "3f9a")

        guard case .notModified = result else {
            Issue.record("Expected notModified, got \(result)")
            return
        }
    }

    @Test func `config.json tells maglev from Java, and an HTML answer is not maglev`() async throws {
        _ = mock(path: "/api/where/config.json", data: Fixtures.loadData(file: "config-maglev.json"))
        #expect(try await service.isMaglevServer())

        dataLoader.removeMappedResponses()
        _ = mock(path: "/api/where/config.json", data: Fixtures.loadData(file: "config-java.json"))
        #expect(try await service.isMaglevServer() == false)

        dataLoader.removeMappedResponses()
        _ = mock(path: "/api/where/config.json", data: Data("<!doctype html><html></html>".utf8), contentType: "text/html; charset=utf-8")
        #expect(try await service.isMaglevServer() == false)

        dataLoader.removeMappedResponses()
        _ = mock(path: "/api/where/config.json", data: Data("<html><body>HTTP Status 404</body></html>".utf8), statusCode: 404, contentType: "text/html;charset=utf-8")
        #expect(try await service.isMaglevServer() == false)
    }

    /// An outage mustn't make a maglev server look like Java: a multi-agency
    /// maglev region would then sync, and show its shared stops twice.
    @Test func `A config.json failure that isn't an HTML page throws`() async {
        _ = mock(path: "/api/where/config.json", data: Data(#"{"code":503}"#.utf8), statusCode: 503)

        await #expect(throws: APIError.self) {
            _ = try await self.service.isMaglevServer()
        }
    }

    /// Only an HTML page means the server lacks the endpoint. A JSON 404, a blank
    /// 200, a 429 or the Java server's `null` for an unknown agency is a failed
    /// attempt, retried later.
    @Test func `Only an HTML page means the endpoint is missing`() {
        #expect(APIError.requestNotFound(response(404, "text/html;charset=utf-8")).meansStopsForAgencyUnsupported)
        #expect(APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "text/html").meansStopsForAgencyUnsupported)

        #expect(!APIError.requestNotFound(response(404, "application/json")).meansStopsForAgencyUnsupported)
        #expect(!APIError.requestNotFound(response(200, "application/json")).meansStopsForAgencyUnsupported)
        #expect(!APIError.requestFailure(response(429, "application/json")).meansStopsForAgencyUnsupported)
        #expect(!APIError.invalidContentType(originalError: nil, expectedContentType: "json", actualContentType: "nothing").meansStopsForAgencyUnsupported)
        #expect(!APIError.networkFailure(nil).meansStopsForAgencyUnsupported)
    }

    @Test func `An old Java server's HTML 404 and an unknown agency's null are told apart`() async {
        _ = mock(path: "/api/where/stops-for-agency/1.json", data: Data("<html><body>HTTP Status 404</body></html>".utf8), statusCode: 404, contentType: "text/html;charset=utf-8")
        _ = mock(path: "/api/where/stops-for-agency/9.json", data: Data("null".utf8))

        do {
            _ = try await service.getStopsForAgency(id: "1")
            Issue.record("Expected the HTML 404 to throw")
        } catch let error as APIError {
            #expect(error.meansStopsForAgencyUnsupported)
        } catch {
            Issue.record("Unexpected error \(error)")
        }

        do {
            _ = try await service.getStopsForAgency(id: "9")
            Issue.record("Expected null to throw")
        } catch let error as APIError {
            #expect(!error.meansStopsForAgencyUnsupported)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
