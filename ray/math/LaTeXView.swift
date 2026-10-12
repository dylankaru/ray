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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var ready = false
        var pending: String?
        var lastRendered: String?
        weak var webView: WKWebView?

        func webView(_ w: WKWebView, didFinish _: WKNavigation!) {
            ready = true
            if let p = pending { render(p) }
        }

        func render(_ latex: String) {
            guard ready else { pending = latex; return }
            guard latex != lastRendered else { return }
            lastRendered = latex
            // JSON-encoding makes it a safe JS string literal
            let data = try? JSONEncoder().encode(latex)
            let lit = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            webView?.evaluateJavaScript("render(\(lit))")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.webView = web

        if let dir = Bundle.main.url(forResource: "katex", withExtension: nil) {
            let html = """
            <html><head>
            <link rel="stylesheet" href="katex.min.css">
            <script src="katex.min.js"></script>
            <style>body{margin:0;color:white;font-size:\(fontSize)px;display:flex;align-items:center;height:100vh;overflow:hidden}</style>
            </head><body><div id="m"></div>
            <script>function render(s){katex.render(s,document.getElementById('m'),{throwOnError:false})}</script>
            </body></html>
            """
            let file = dir.appendingPathComponent("index.html")
            try? html.write(to: file, atomically: true, encoding: .utf8)  // see note below
            web.loadFileURL(file, allowingReadAccessTo: dir)
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.render(latex)
    }
}
