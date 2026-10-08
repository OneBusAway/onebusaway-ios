//
//  HyperconnectivityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Network
import Testing
@testable import OBAKit

/// Covers the vendored Hyperconnectivity in `OBAKit/ThirdParty/Hyperconnectivity`,
/// including regressions for the `OBA:` fixes made there.
@Suite(.serialized)
struct HyperconnectivityTests {

    // MARK: - Percentage

    @Test func `Percentage clamps to 0...100`() {
        #expect(Percentage(-5).value == 0)
        #expect(Percentage(150).value == 100)
        #expect(Percentage(42).value == 42)
    }

    @Test func `Percentage of a zero total is zero`() {
        #expect(Percentage(UInt(3), outOf: 0).value == 0)
        #expect(Percentage(UInt(1), outOf: 4).value == 25)
    }

    // MARK: - Connection and ConnectivityResult

    private struct FakePath: NetworkPath {
        var interfaces: Set<NWInterface.InterfaceType>
        var isExpensive = false

        func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
            interfaces.contains(type)
        }
    }

    @Test func `Connection prefers ethernet, then wifi, then cellular`() {
        #expect(Connection(FakePath(interfaces: [.cellular, .wifi, .wiredEthernet])) == .ethernet)
        #expect(Connection(FakePath(interfaces: [.cellular, .wifi])) == .wifi)
        #expect(Connection(FakePath(interfaces: [.cellular])) == .cellular)
        #expect(Connection(FakePath(interfaces: [])) == .disconnected)
    }

    @Test func `Result is connected only when the success threshold is met`() {
        let path = FakePath(interfaces: [.cellular], isExpensive: true)
        let half = Percentage(50)

        let met = ConnectivityResult(path: path, successfulChecks: 1, totalChecks: 2, successThreshold: half)
        #expect(met.isConnected)
        #expect(met.isExpensive)
        #expect(met.connection == .cellular)

        let missed = ConnectivityResult(path: path, successfulChecks: 0, totalChecks: 2, successThreshold: half)
        #expect(missed.isConnected == false)
    }

    // MARK: - Response validators

    private let response = URLResponse()

    @Test func `Contains validator matches a substring`() {
        let validator = ResponseContainsStringValidator()
        #expect(validator.isResponseValid(response, data: Data("<BODY>Success</BODY>".utf8)))
        #expect(validator.isResponseValid(response, data: Data("Failure".utf8)) == false)
    }

    @Test func `Equality validator ignores surrounding whitespace only`() {
        let validator = ResponseStringEqualityValidator()
        #expect(validator.isResponseValid(response, data: Data("  Success\n".utf8)))
        #expect(validator.isResponseValid(response, data: Data("Success!".utf8)) == false)
    }

    /// Upstream sized the search range in Characters rather than UTF-16 units, so
    /// each emoji ahead of the match pushed the closing tag out of range.
    @Test func `Regex validator searches all of a non-ASCII response`() {
        let validator = ResponseRegExValidator()
        let body = String(repeating: "🚌", count: 20) + "<BODY>Success</BODY>"
        #expect(validator.isResponseValid(response, data: Data(body.utf8)))
        #expect(validator.isResponseValid(response, data: Data("<BODY>Nope</BODY>".utf8)) == false)
    }

    // MARK: - Publisher

    private func firstResult(checking urls: [URL]) async -> ConnectivityResult? {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubConnectivityURLProtocol.self]
        let configuration = HyperconnectivityConfiguration(
            connectivityURLs: urls,
            urlSessionConfiguration: sessionConfiguration
        )
        for await result in ConnectivityPublisher(configuration: configuration).values {
            return result
        }
        return nil
    }

    /// Upstream let a failed request end the merged stream, so one unreachable URL
    /// reported no Internet whenever its failure arrived before the other URL's
    /// success. This passes in either order now.
    @Test(.timeLimit(.minutes(1)))
    func `One failing URL does not mask a successful one`() async throws {
        let result = try #require(await firstResult(checking: [StubConnectivityURLProtocol.failing, StubConnectivityURLProtocol.succeeding]))
        #expect(result.isConnected)
    }

    @Test(.timeLimit(.minutes(1)))
    func `No passing check means no connectivity`() async throws {
        let result = try #require(await firstResult(checking: [StubConnectivityURLProtocol.failing, StubConnectivityURLProtocol.invalid]))
        #expect(result.isConnected == false)
    }
}

/// Answers by host, so it needs no shared mutable state: `failing` errors out,
/// `succeeding` returns "Success", and `invalid` returns a body the default
/// validator rejects.
private nonisolated final class StubConnectivityURLProtocol: URLProtocol {
    static let failing = URL(string: "https://failing.connectivity.test/")!
    static let succeeding = URL(string: "https://succeeding.connectivity.test/")!
    static let invalid = URL(string: "https://invalid.connectivity.test/")!

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }

        if url.host() == Self.failing.host() {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        let succeeds = url.host() == Self.succeeding.host()
        let body = succeeds ? "<HTML><BODY>Success</BODY></HTML>" : "<HTML><BODY>Nope</BODY></HTML>"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
