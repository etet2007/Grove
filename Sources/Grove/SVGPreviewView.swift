import SwiftUI
import WebKit

/// SVG is loaded as an isolated image: no scripts, file access, or network resources.
struct SVGPreviewView: NSViewRepresentable {
    let data: Data

    final class Coordinator {
        var displayedData: Data?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.displayedData != data else { return }
        context.coordinator.displayedData = data
        view.loadHTMLString(Self.html(data), baseURL: nil)
    }

    static func html(_ data: Data) -> String {
        """
        <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden}body{display:flex;align-items:center;justify-content:center}img{width:100%;height:100%;object-fit:contain}p{color:#888;font:12px system-ui}</style></head>
        <body><img src="data:image/svg+xml;base64,\(data.base64EncodedString())" alt="SVG"></body></html>
        """
    }
}
