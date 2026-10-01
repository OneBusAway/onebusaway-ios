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

    @Test func testWebViewInitialization() {
        let webView = DocumentWebView()
        #expect(webView != nil)
    }
    
    @Test func testActionButtonHandlerName() {
        #expect(DocumentWebView.actionButtonHandlerName == "actionButtonClicked")
    }

    @Test func testSetPageContentDoesNotCrash() {
        let webView = DocumentWebView()
        // Ensure that injecting HTML and a button doesn't trap due to forced unwraps
        // of missing resources (e.g. document_web_view_content.html not being bundled)
        webView.setPageContent("<h1>Test Content</h1>", actionButtonTitle: "Test Button")
        
        // At this point we can't synchronously inspect the WKWebView loaded HTML without
        // an active navigation delegate, but reaching this line confirms that the pageBody
        // was read successfully from the framework bundle.
        #expect(webView.configuration != nil)
    }
}
