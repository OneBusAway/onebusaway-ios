//
//  DocumentWebView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import WebKit
import UIKit

/// A web view expressly meant for rendering local content, like documents and credits.
///
/// Set content using the `setPageContent()` method, which will wrap the specified
/// HTML fragment with an HTML document, allowing for comfortable reading on a phone.
class DocumentWebView: WKWebView {

    static let actionButtonHandlerName = "actionButtonClicked"

    /// Pass along either a plain string or an HTML fragment to render it in the web view.
    /// 
    /// Example: You can pass in either values like "hello world" or `"<h1>Hello</h1><p>World</p>"`
    /// 
    /// - Parameter htmlFragment: The content to render in the web view.
    /// - Parameter actionButtonTitle: The title of the optional button shown at the bottom of the web view.
    func setPageContent(_ htmlFragment: String, actionButtonTitle: String? = nil) {
        var content = pageBody.replacingOccurrences(of: "{{{oba_page_content}}}", with: htmlFragment)
        content = content.replacingOccurrences(of: "{{{accent_color}}}", with: accentHexColor)
        content = content.replacingOccurrences(of: "{{{accent_foreground_color}}}", with: accentForegroundColor)

        if let actionButtonTitle {
            let buttonText = """
            <div class="actions__button-container">
                <button type="button" class="actions__button-container__button" onclick="window.webkit.messageHandlers.actionButtonClicked.postMessage({})">
                    \(actionButtonTitle)
                </button>
            </div>
            """
            content = content.replacingOccurrences(of: "{{{oba_page_actions}}}", with: buttonText)
        }

        loadHTMLString(content, baseURL: nil)
    }

    private var accentForegroundColor: String {
        let hex = UIColor.accentColor.contrastingTextColor.toHex!
        return "#\(hex)"
    }

    private var accentHexColor: String {
        let hex = UIColor.accentColor.toHex!
        return "#\(hex)"
    }

    private var pageBody: String {
        let frameworkBundle = Bundle(for: type(of: self))
        let htmlPath = frameworkBundle.path(forResource: "document_web_view_content", ofType: "html")!
        return try! String(contentsOfFile: htmlPath) // swiftlint:disable:this force_try
    }
}
