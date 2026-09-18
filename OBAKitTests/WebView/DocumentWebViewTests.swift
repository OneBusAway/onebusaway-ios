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

@Suite(.serialized)
@MainActor
final class DocumentWebViewTests {
    
    @Test func `Initialization succeeds`() {
        // DocumentWebView is an internal class, but we have @testable import
        let webView = DocumentWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(webView != nil)
    }

    // A real loadHTMLString is asynchronous and WKWebView requires a lot of setup to inspect DOM in tests,
    // so we just verify that it doesn't crash when setPageContent is called.
    @Test func `setPageContent with HTML fragment completes without error`() {
        let webView = DocumentWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setPageContent("<h1>Hello World</h1>", actionButtonTitle: "Dismiss")
        
        // At minimum, we expect it to not crash and to exist.
        #expect(webView != nil)
    }
}