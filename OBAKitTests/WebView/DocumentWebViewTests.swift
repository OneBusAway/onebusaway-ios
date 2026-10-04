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
    private final class NavigationDelegate: NSObject, WKNavigationDelegate, @unchecked Sendable {
        var onFinish: ((WKWebView) -> Void)?
        var onError: ((Error) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish?(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError?(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError?(error)
        }
    }

    /// Thread-safe wrapper to ensure the continuation is resumed exactly once.
    private final class CancellableContinuation: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?
        private var hasResumed = false
        private let lock = NSLock()

        func set(_ c: CheckedContinuation<Void, Error>) {
            var storedResult: Result<Void, Error>?
            lock.lock()
            if hasResumed {
                lock.unlock()
                return
            }
            if let res = result {
                hasResumed = true
                storedResult = res
            } else {
                continuation = c
            }
            lock.unlock()
            
            if let res = storedResult {
                switch res {
                case .success: c.resume()
                case .failure(let e): c.resume(throwing: e)
                }
            }
        }

        func resume() {
            var cToResume: CheckedContinuation<Void, Error>?
            lock.lock()
            if hasResumed || result != nil {
                lock.unlock()
                return
            }
            if let c = continuation {
                hasResumed = true
                cToResume = c
                continuation = nil
            } else {
                result = .success(())
            }
            lock.unlock()
            
            cToResume?.resume()
        }

        func resume(throwing error: Error) {
            var cToResume: CheckedContinuation<Void, Error>?
            lock.lock()
            if hasResumed || result != nil {
                lock.unlock()
                return
            }
            if let c = continuation {
                hasResumed = true
                cToResume = c
                continuation = nil
            } else {
                result = .failure(error)
            }
            lock.unlock()
            
            cToResume?.resume(throwing: error)
        }
    }

    private struct TimeoutError: Error {}

    /// Verifies that the internal JS action button handler name is correct.
    @Test func testActionButtonHandlerName() {
        #expect(DocumentWebView.actionButtonHandlerName == "actionButtonClicked")
    }

    /// Verifies that setting page content injects the HTML and button appropriately.
    @Test func testSetPageContentRendersHTMLWithButton() async throws {
        let webView = DocumentWebView()
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        let cancellable = CancellableContinuation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        cancellable.set(continuation)
                        delegate.onFinish = { _ in
                            cancellable.resume()
                        }
                        delegate.onError = { error in
                            cancellable.resume(throwing: error)
                        }

                        DispatchQueue.main.async {
                            webView.setPageContent("<h1>Test Content</h1>", actionButtonTitle: "Test Button")
                        }
                    }
                } onCancel: {
                    cancellable.resume(throwing: CancellationError())
                    DispatchQueue.main.async {
                        webView.stopLoading()
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw TimeoutError()
            }

            try await group.next()
            group.cancelAll()
        }

        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
        #expect(html.contains("Test Content"))
        #expect(html.contains("Test Button"))
        #expect(html.contains("actionButtonClicked"))
    }

    /// Verifies that setting page content without a button title omits the action button.
    @Test func testSetPageContentRendersHTMLWithoutButton() async throws {
        let webView = DocumentWebView()
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        let cancellable = CancellableContinuation()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        cancellable.set(continuation)
                        delegate.onFinish = { _ in
                            cancellable.resume()
                        }
                        delegate.onError = { error in
                            cancellable.resume(throwing: error)
                        }

                        DispatchQueue.main.async {
                            webView.setPageContent("<h1>Test Content</h1>", actionButtonTitle: nil)
                        }
                    }
                } onCancel: {
                    cancellable.resume(throwing: CancellationError())
                    DispatchQueue.main.async {
                        webView.stopLoading()
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw TimeoutError()
            }

            try await group.next()
            group.cancelAll()
        }

        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
        #expect(html.contains("Test Content"))
        #expect(!html.contains("Test Button"))
        #expect(!html.contains("actionButtonClicked"))
    }
}
