import Foundation
import UIKit
import WebKit

/// 用隐藏的 WKWebView 重新获取 Cloudflare 的 `cf_clearance`。
///
/// 背景：本站开着 Cloudflare 托管质询，URLSession 不可能自己算出 Turnstile 的答案，
/// 裸请求一律 403（`cf-mitigated: challenge`）。唯一可行的路径是让 WebView 过一次验证，
/// 再把 `cf_clearance` 同步到 `HTTPCookieStorage.shared` 给 URLSession 用。
/// 该 Cookie 有效期通常只有几十分钟到几小时，过期后原生请求会重新开始 403，
/// 所以需要在检测到 403 时自动刷新一次。
///
/// 所有状态都只在主线程读写（WKWebView 本身也只能在主线程用），因此不需要加锁。
final class CloudflareManager: NSObject {

    static let shared = CloudflareManager()

    /// 刷新用的首页。选首页而不是具体板块，避免把业务参数掺进来。
    private let probeURL = URL(string: "https://www.4d4y.com/forum/")!

    /// 单次刷新最长等待时间
    private let timeout: TimeInterval = 40
    /// 轮询间隔
    private let pollInterval: TimeInterval = 1.0
    /// 两次刷新之间的冷却时间。
    /// 刚刷新完又立刻 403，说明不是 clearance 过期的问题，再刷也没用，
    /// 直接拒绝可以避免请求风暴。
    private let cooldown: TimeInterval = 30

    private var webView: WKWebView?
    private var isRefreshing = false
    private var lastAttempt: Date?
    private var waiters: [(Bool) -> Void] = []
    private var deadline: Date?

    private override init() {
        super.init()
    }

    // MARK: - Public

    /// 刷新 clearance。并发调用会被合并成一次真实刷新。
    /// - Returns: 是否成功拿到了可用的 clearance
    func refreshClearance() async -> Bool {
        await withCheckedContinuation { continuation in
            var resumed = false
            self.enqueueRefresh { success in
                // withCheckedContinuation 必须且只能恢复一次
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Refresh pipeline

    private func enqueueRefresh(_ completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }

            // 已经有一次刷新在跑：挂上去等同一个结果，不要重复开 WebView
            if self.isRefreshing {
                self.waiters.append(completion)
                return
            }

            if let last = self.lastAttempt, Date().timeIntervalSince(last) < self.cooldown {
                print("[Cloudflare] Refresh skipped (cooldown, \(Int(self.cooldown - Date().timeIntervalSince(last)))s left)")
                completion(false)
                return
            }

            self.isRefreshing = true
            self.lastAttempt = Date()
            self.deadline = Date().addingTimeInterval(self.timeout)
            self.waiters.append(completion)

            self.startRefresh()
        }
    }

    private func startRefresh() {
        print("[Cloudflare] Refreshing clearance via hidden WebView...")

        let configuration = WKWebViewConfiguration()
        // 必须用 .default()，这样才和登录用的 WebView 共享同一个 Cookie 存储
        configuration.websiteDataStore = .default()

        // 尺寸不能给 0：Turnstile 需要真实布局才会执行。
        // 用接近真机的尺寸，但完全透明且不接受点击，用户无感。
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.customUserAgent = WebClientConfig.userAgent
        webView.navigationDelegate = self
        webView.alpha = 0
        webView.isUserInteractionEnabled = false

        // 必须挂进窗口层级，否则 WebKit 会把它当作离屏视图限制 JS/渲染，
        // Turnstile 可能永远不执行
        if let window = Self.keyWindow {
            window.insertSubview(webView, at: 0)
        }

        self.webView = webView

        var request = URLRequest(url: probeURL)
        WebClientConfig.applyBrowserHeaders(to: &request)
        webView.load(request)

        schedulePoll()
    }

    private func schedulePoll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            self?.poll()
        }
    }

    private func poll() {
        guard isRefreshing, let webView = webView else { return }

        if let deadline = deadline, Date() >= deadline {
            print("[Cloudflare] Refresh timed out (challenge may need user interaction)")
            finish(false)
            return
        }

        webView.evaluateJavaScript(ForumPageProbe.javaScript) { [weak self] result, _ in
            guard let self = self, self.isRefreshing else { return }

            let state = ForumPageProbe.parse(result)
            if state.isReady {
                print("[Cloudflare] Challenge passed, syncing cookies...")
                self.syncCookiesAndFinish()
            } else {
                self.schedulePoll()
            }
        }
    }

    private func syncCookiesAndFinish() {
        guard let webView = webView else {
            finish(false)
            return
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            let storage = HTTPCookieStorage.shared
            var syncedClearance = false

            for cookie in cookies where cookie.domain.contains("4d4y.com") {
                if let existing = storage.cookies?.first(where: {
                    $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
                }) {
                    storage.deleteCookie(existing)
                }
                storage.setCookie(cookie)
                if cookie.name == "cf_clearance" {
                    syncedClearance = true
                }
            }

            print("[Cloudflare] Synced \(cookies.count) cookies, cf_clearance=\(syncedClearance)")

            // 把刷新后的 Cookie 一并落盘到当前账号，避免下次冷启动又要重来
            LoginManager.shared.saveCookies()

            self.finish(true)
        }
    }

    private func finish(_ success: Bool) {
        // 保证在主线程收尾（getAllCookies 的回调就在主线程，这里再兜一次底）
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.finish(success) }
            return
        }

        isRefreshing = false
        deadline = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil

        let callbacks = waiters
        waiters = []
        callbacks.forEach { $0(success) }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

// MARK: - WKNavigationDelegate

extension CloudflareManager: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        // 挑战页自我跳转会产生 -999（cancelled），属正常现象，交给轮询继续等
        guard nsError.code != NSURLErrorCancelled else { return }

        print("[Cloudflare] Navigation failed: \(error.localizedDescription)")
        finish(false)
    }
}
