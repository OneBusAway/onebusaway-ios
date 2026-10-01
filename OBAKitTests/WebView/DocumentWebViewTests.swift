//
//  DocumentWebViewTests.swift
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

/// Tests for the `DocumentWebView` component.
@Suite(.serialized)
@MainActor
final class DocumentWebViewTests {

    /// Helper delegate to bridge WKNavigationDelegate callbacks to async/await.
    private class NavigationDelegate: NSObject, WKNavigationDelegate {
        var onFinish: ((WKWebView) -> Void)?
        var onError: ((Error) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError?(error)
        }
    }

    /// Verifies that `DocumentWebView` can be initialized.
    @Test func testWebViewInitialization() {
        let webView = DocumentWebView()
        #expect(webView != nil)
    }
    
    /// Verifies that the internal JS action button handler name is correct.
    @Test func testActionButtonHandlerName() {
        #expect(DocumentWebView.actionButtonHandlerName == "actionButtonClicked")
    }

    /// Verifies that setting page content injects the HTML and button appropriately without crashing.
    @Test func testSetPageContentDoesNotCrash() async throws {
        let webView = DocumentWebView()
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate
        
        webView.setPageContent("<h1>Test Content</h1>", actionButtonTitle: "Test Button")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.onFinish = { _ in
                continuation.resume()
            }
            delegate.onError = { error in
                continuation.resume(throwing: error)
            }
        }
        
        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
        #expect(html.contains("Test Content"))
        #expect(html.contains("Test Button"))
    }
}
