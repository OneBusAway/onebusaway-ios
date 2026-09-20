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
    
    @Test func `buildPageContent replaces tokens with HTML fragment and action button`() {
        let webView = DocumentWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let result = webView.buildPageContent("<h1>Hello World</h1>", actionButtonTitle: "Dismiss")
        
        #expect(result.contains("<h1>Hello World</h1>"))
        #expect(result.contains("Dismiss"))
        #expect(result.contains("actionButtonClicked"))
    }
    
    @Test func `buildPageContent replaces tokens without action button when title is nil`() {
        let webView = DocumentWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let result = webView.buildPageContent("<h1>Hello World</h1>", actionButtonTitle: nil)
        
        #expect(result.contains("<h1>Hello World</h1>"))
        #expect(!result.contains("actionButtonClicked"))
    }
}
