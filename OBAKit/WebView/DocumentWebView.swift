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

    /// Pass along either a plain string or an HTML fragment to render it in the web view.
    ///
    /// Example: You can pass in either values like "hello world" or `"<h1>Hello</h1><p>World</p>"`
    ///
    /// - Parameter htmlFragment: The content to render in the web view.
    func setPageContent(_ htmlFragment: String) {
        let content = pageBody.replacingOccurrences(of: "{{{oba_page_content}}}", with: htmlFragment)
        loadHTMLString(content, baseURL: nil)
    }

    private var pageBody: String {
        """
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN">
        <html>
            <head>
                <meta content='initial-scale=1.0, user-scalable=no' name='viewport'>
                    <style type='text/css'>
                        html {
                            overflow-x: hidden;
                        }
                        body {
                            -webkit-text-size-adjust: none;
                            font-family: system, -apple-system, "Helvetica Neue", Helvetica, sans-serif;
                            padding: 8px;
                            overflow-x: hidden;
                            background-color:#000;
                            color:#fff;
                        }

                        @media screen and (prefers-color-scheme:light) {
                            body {
                                background-color:#fff;
                                color:#000;
                            }
                        }

                        code, pre {
                            max-width: 300px;
                            overflow-x: hidden;
                        }

                        code h1 {
                            font-size: 14px;
                        }

                        h1 {
                            font-size: 18px;
                        }

                        h2 {
                            font-size: 14px;
                        }
                    </style>
            </head>
            <body>
                {{{oba_page_content}}}
            </body>
        </html>
        """
    }
}
