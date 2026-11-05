import SwiftUI
import UIKit
import WebKit
import OSLog

struct ContactPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            InAppBrowser(url: AppEndpoints.contactURL.absoluteString, showsNavigationControls: true)
                .navigationTitle("Contact Us").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("contact.done") } }
        }
    }
}

struct InAppBrowser: View {
    let url: String
    let showsNavigationControls: Bool
    @State private var isLoading = true

    init(url: String, showsNavigationControls: Bool = false) {
        self.url = url
        self.showsNavigationControls = showsNavigationControls
    }

    var body: some View {
        ZStack {
            if !showsNavigationControls { Color.black.ignoresSafeArea() }
            BrowserControllerView(urlString: url, isLoading: $isLoading, showsNavigationControls: showsNavigationControls)
                .ignoresSafeArea()

            if isLoading {
                BrowserLoadingOverlay()
                    .accessibilityIdentifier("browser.loading")
            }
        }
    }

}

private struct BrowserLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
        }
    }
}

struct BrowserControllerView: UIViewControllerRepresentable {
    let urlString: String
    @Binding var isLoading: Bool
    let showsNavigationControls: Bool

    init(urlString: String, isLoading: Binding<Bool>, showsNavigationControls: Bool) {
        self.urlString = urlString
        self._isLoading = isLoading
        self.showsNavigationControls = showsNavigationControls
    }

    func makeUIViewController(context: Context) -> BrowserViewController {
        let controller = BrowserViewController(showsNavigationControls: showsNavigationControls)
        controller.delegate = context.coordinator
        controller.loadURL(urlString)
        return controller
    }

    func updateUIViewController(_ uiViewController: BrowserViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    class Coordinator: BrowserViewControllerDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webViewDidStartLoading() {
            DispatchQueue.main.async {
                self.isLoading = true
            }
        }

        func webViewDidFinishLoading() {
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
}

@MainActor
protocol BrowserViewControllerDelegate: AnyObject {
    func webViewDidStartLoading()
    func webViewDidFinishLoading()
}

class BrowserViewController: UIViewController {
    weak var delegate: BrowserViewControllerDelegate?

    private let showsNavigationControls: Bool
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "WebView")

    init(showsNavigationControls: Bool = false) {
        self.showsNavigationControls = showsNavigationControls
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    private var webView: WKWebView!
    private var backButton: UIBarButtonItem!
    private var toolbar: UIToolbar!
    private var pendingURLString: String?
    private var didStartLoad = false
    private var lastRequest: URLRequest?
    private var failureView: UIView?
    private var observedCookies: [HTTPCookie] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()

        if let urlString = pendingURLString {
            loadURL(urlString)
            pendingURLString = nil
        }
    }

    private func setupWebView() {
        if !showsNavigationControls { view.backgroundColor = .black }
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = AppEndpoints.defaultUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.accessibilityIdentifier = "browser.webView"
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true

        view.addSubview(webView)
        if showsNavigationControls { setupToolbar() }

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: showsNavigationControls ? view.leadingAnchor : view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: showsNavigationControls ? view.trailingAnchor : view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: showsNavigationControls ? toolbar.topAnchor : view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupToolbar() {
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        backButton = UIBarButtonItem(title: "Back", style: .plain, target: self, action: #selector(handleBackTap))
        backButton.isEnabled = false
        let reload = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadPage))
        let contact = UIBarButtonItem(title: "Contact Us", style: .plain, target: self, action: #selector(contactUs))
        contact.accessibilityIdentifier = "browser.contact"
        toolbar.items = [backButton, reload, UIBarButtonItem(systemItem: .flexibleSpace), contact]
        view.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func reloadPage() {
        failureView?.removeFromSuperview()
        failureView = nil
        if let lastRequest { webView.load(lastRequest) }
        else { webView.reload() }
    }
    @objc private func contactUs() { webView.load(URLRequest(url: AppEndpoints.contactURL)) }

    func loadURL(_ urlString: String) {
        guard webView != nil else {
            pendingURLString = urlString
            return
        }
        guard !didStartLoad else { return }
        if !showsNavigationControls {
            // The launch WebView uses the supplied implementation's direct load.
            guard let url = URL(string: urlString) else { return }
            didStartLoad = true
            let request = URLRequest(url: url)
            lastRequest = request
            webView.load(request)
            return
        }
        guard let url = ContentURL.validated(urlString) else {
            delegate?.webViewDidFinishLoading()
            return
        }
        didStartLoad = true
        Task { @MainActor in
            BrowserSession.restore()
            let store = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in HTTPCookieStorage.shared.cookies ?? [] {
                await store.setCookie(cookie)
            }
            observedCookies = await store.allCookies()
            store.add(self)
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func handleBackTap() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    private func updateBackButtonVisibility() {
        backButton?.isEnabled = webView.canGoBack
    }

    private func loadingFailed(_ error: Error) {
        delegate?.webViewDidFinishLoading()
        let failure = error as NSError
        guard failure.domain != NSURLErrorDomain || failure.code != NSURLErrorCancelled else { return }
        logger.error("Navigation failed: \(failure.domain, privacy: .public) (\(failure.code))")
        #if DEBUG
        print("WEBVIEW_FAILURE domain=\(failure.domain) code=\(failure.code)")
        #endif
        if let failedURL = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
           ContentURL.validated(failedURL.absoluteString) != nil {
            lastRequest = URLRequest(url: failedURL)
        }
        guard showsNavigationControls else {
            showLoadFailure(failure)
            return
        }
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Unable to load page", message: "Check your connection and try again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in guard let self else { return }
            if let request = self.lastRequest { self.webView.load(request) }
            else { self.webView.reload() }
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func showLoadFailure(_ error: NSError) {
        failureView?.removeFromSuperview()
        let message = UILabel()
        message.text = error.domain == NSURLErrorDomain && error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
            ? "This page requires a secure connection." : "Unable to load page. Try again."
        message.textColor = .label
        message.font = .preferredFont(forTextStyle: .body)
        message.textAlignment = .center
        message.numberOfLines = 0
        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.accessibilityIdentifier = "browser.retry"
        retry.addTarget(self, action: #selector(reloadPage), for: .touchUpInside)
        let panel = UIStackView(arrangedSubviews: [message, retry])
        panel.axis = .vertical
        panel.spacing = 12
        panel.backgroundColor = .systemBackground
        panel.layer.cornerRadius = 16
        panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -40),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        ])
        failureView = panel
    }
}

extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url, ContentURL.validated(url.absoluteString) != nil {
            lastRequest = navigationAction.request
        }
        guard showsNavigationControls else {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if ["http", "https", "about", "blob"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame != false {
                lastRequest = navigationAction.request
            }
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if ["mailto", "tel", "sms"].contains(scheme) || navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failureView?.removeFromSuperview()
        failureView = nil
        delegate?.webViewDidStartLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logger.error("Web content process terminated; reloading the current page")
        reloadPage()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delegate?.webViewDidFinishLoading()
        updateBackButtonVisibility()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }
}

extension BrowserViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if showsNavigationControls {
                if ContentURL.validated(url.absoluteString) != nil { webView.load(navigationAction.request) }
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        return nil
    }
}

extension BrowserViewController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            let cookies = await cookieStore.allCookies()
            // Remove cookies deleted by the website (for example on sign-out).
            for previous in observedCookies where !cookies.contains(where: {
                $0.name == previous.name && $0.domain == previous.domain && $0.path == previous.path
            }) {
                HTTPCookieStorage.shared.deleteCookie(previous)
            }
            observedCookies = cookies
            for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
            BrowserSession.persist()
        }
    }
}
