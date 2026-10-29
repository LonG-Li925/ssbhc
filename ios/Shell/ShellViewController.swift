import UIKit
import WebKit

final class ShellViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var server: LocalHTTPServer?
    private var splash: UILabel?
    private let serverPort: UInt16 = 18888
    private let onlineURL = "http://36.134.112.211:66/"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.075, blue: 0.10, alpha: 1)

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.allowsAirPlayForMediaPlayback = true

        let wv = WKWebView(frame: view.bounds, configuration: cfg)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.bounces = false
        wv.scrollView.isScrollEnabled = false
        wv.allowsBackForwardNavigationGestures = false
        view.addSubview(wv)
        webView = wv

        let label = UILabel()
        label.text = "时尚百货城\n\n正在加载资源…"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.91, green: 0.925, blue: 0.97, alpha: 1)
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.backgroundColor = view.backgroundColor
        label.frame = view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
        splash = label

        startServing()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    private func startServing() {
        // ① 优先 App 内置 www 目录 (资源全离线)
        if let bundled = Bundle.main.url(forResource: "www", withExtension: nil) {
            startLocal(root: bundled)
            return
        }
        // ② 其次 Documents/www (首启动下载过一次)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("www")
        if FileManager.default.fileExists(atPath: docs.appendingPathComponent("index.html").path) {
            startLocal(root: docs)
            return
        }
        // ③ 兜底: 直连线上
        load(onlineURL)
    }

    private func startLocal(root: URL) {
        do {
            let s = try LocalHTTPServer(root: root, port: serverPort)
            s.start()
            server = s
            load("http://127.0.0.1:\(serverPort)/")
        } catch {
            load(onlineURL)
        }
    }

    private func load(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        webView.load(req)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let s = splash else { return }
        UIView.animate(withDuration: 0.22, animations: { s.alpha = 0 }) { _ in
            s.removeFromSuperview()
        }
        splash = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // 本地服务异常时退回线上
        if webView.url?.host == "127.0.0.1" {
            load(onlineURL)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "127.0.0.1" || url.host == "36.134.112.211" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
            return
        }
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    // MARK: - WKUIDelegate (target=_blank)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
