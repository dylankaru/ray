//
//  LaTeXView.swift
//  ray
//
//  Created by Dylan Karunanayake on 9/10/2026.
//

import SwiftUI
import WebKit

struct LaTeXView: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat
    var useSystemFont: Bool = true // Set to true for modern macOS SF Pro sans-serif font

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let fontOverrideCSS = useSystemFont ? """
        .katex {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
        }
        """ : ""

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: transparent;
                    color: white;
                    font-size: \(fontSize)px;
                    display: flex;
                    align-items: center;
                    height: 100vh;
                    overflow: hidden;
                }
                \(fontOverrideCSS)
            </style>
        </head>
        <body>
            <div id="math"></div>
            <script>
                katex.render(String.raw`\(latex)`, document.getElementById('math'), {
                    throwOnError: false
                });
            </script>
        </body>
        </html>
        """
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
