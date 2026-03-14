import SwiftUI
import WebKit

struct ReportDetailView: View {
    let report: ReportFile
    let toolkitPath: String

    var body: some View {
        ReportWebView(reportPath: report.path)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReportWebView: NSViewRepresentable {
    let reportPath: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadReport(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadReport(into: webView)
    }

    private func loadReport(into webView: WKWebView) {
        guard let markdown = try? String(contentsOfFile: reportPath, encoding: .utf8) else {
            webView.loadHTMLString("<p>Could not load report.</p>", baseURL: nil)
            return
        }

        let escapedMarkdown = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            :root { color-scheme: light dark; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                font-size: 13px;
                line-height: 1.6;
                padding: 20px;
                max-width: 900px;
                margin: 0 auto;
                color: var(--text);
                background: transparent;
            }
            @media (prefers-color-scheme: dark) {
                :root { --text: #e0e0e0; --bg: #1e1e1e; --border: #333; --code-bg: #2d2d2d; }
            }
            @media (prefers-color-scheme: light) {
                :root { --text: #1d1d1f; --bg: #ffffff; --border: #d2d2d7; --code-bg: #f5f5f7; }
            }
            h1 { font-size: 1.8em; font-weight: 700; }
            h2 { font-size: 1.4em; font-weight: 600; border-bottom: 1px solid var(--border); padding-bottom: 6px; }
            h3 { font-size: 1.1em; font-weight: 600; }
            table { border-collapse: collapse; width: 100%; margin: 12px 0; }
            th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
            th { background: var(--code-bg); font-weight: 600; }
            code { background: var(--code-bg); padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
            pre { background: var(--code-bg); padding: 12px; border-radius: 6px; overflow-x: auto; }
            ul, ol { padding-left: 24px; }
            hr { border: none; border-top: 1px solid var(--border); margin: 16px 0; }
            strong { font-weight: 600; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(escapedMarkdown)`);
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}
