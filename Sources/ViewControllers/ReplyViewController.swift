import UIKit
import WebKit

protocol ReplyViewControllerDelegate: AnyObject {
    func replyViewControllerDidPost(_ controller: ReplyViewController)
    func replyViewControllerDidCancel(_ controller: ReplyViewController)
}

class ReplyViewController: UIViewController {

    weak var delegate: ReplyViewControllerDelegate?

    private let tid: Int
    private let reppost: Int?  // The post ID being replied to (for quote-reply)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let headerLabel = UILabel()  // Shows "回复楼主" or "回复 #X楼"
    private let contentTextView = UITextView()
    private let submitButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var webView: WKWebView?
    private var formhash: String?
    private var isSubmitting = false

    /// Initialize for a new thread reply
    init(tid: Int) {
        self.tid = tid
        self.reppost = nil
        super.init(nibName: nil, bundle: nil)
    }

    /// Initialize for replying to a specific post
    init(tid: Int, reppost: Int) {
        self.tid = tid
        self.reppost = reppost
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadReplyPage()
    }

    private func setupUI() {
        title = "回复"
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = Theme.primary

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        setupHeaderLabel()
        setupContentField()
        setupSubmitButton()
        setupLoadingIndicator()
    }

    private func setupHeaderLabel() {
        headerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        headerLabel.textColor = Theme.secondaryText

        if let reppost = reppost {
            headerLabel.text = "回复 #\(reppost) 楼"
        } else {
            headerLabel.text = "回复楼主"
        }

        contentView.addSubview(headerLabel)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    private func setupContentField() {
        let label = UILabel()
        label.text = "回复内容"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        contentTextView.font = .systemFont(ofSize: 16)
        contentTextView.backgroundColor = Theme.muted
        contentTextView.textColor = Theme.foreground
        contentTextView.layer.borderWidth = 1
        contentTextView.layer.borderColor = Theme.border.cgColor
        contentTextView.layer.cornerRadius = 8
        contentTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)

        contentView.addSubview(label)
        contentView.addSubview(contentTextView)

        label.translatesAutoresizingMaskIntoConstraints = false
        contentTextView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            contentTextView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            contentTextView.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            contentTextView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

    private func setupSubmitButton() {
        submitButton.setTitle("提交回复", for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        submitButton.backgroundColor = Theme.primary
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = 8
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        contentView.addSubview(submitButton)

        submitButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            submitButton.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 20),
            submitButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            submitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            submitButton.heightAnchor.constraint(equalToConstant: 50),
            submitButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func setupLoadingIndicator() {
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        submitButton.addSubview(loadingIndicator)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor)
        ])
    }

    private func loadReplyPage() {
        // Create hidden WKWebView to handle Cloudflare
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebClientConfig.userAgent
        webView.navigationDelegate = self
        webView.isHidden = true
        self.webView = webView
        view.addSubview(webView)

        // Build reply URL with reppost if specified
        var replyURLString = "https://www.4d4y.com/forum/post.php?action=reply&tid=\(tid)"
        if let reppost = reppost {
            replyURLString += "&reppost=\(reppost)"
        }

        print("[Reply] Loading reply page: \(replyURLString)")
        let replyURL = URL(string: replyURLString)!
        webView.load(URLRequest(url: replyURL))
    }

    @objc private func cancelTapped() {
        delegate?.replyViewControllerDidCancel(self)
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        guard !isSubmitting else { return }

        guard let message = contentTextView.text, !message.isEmpty else {
            showAlert(title: "错误", message: "请输入回复内容")
            return
        }

        guard let formhash = formhash else {
            showAlert(title: "提示", message: "正在加载表单数据，请稍后再试")
            return
        }

        isSubmitting = true
        submitButton.setTitle("", for: .normal)
        loadingIndicator.startAnimating()

        submitReplyViaWebView(message: message, formhash: formhash)
    }

    private func submitReplyViaWebView(message: String, formhash: String) {
        guard let webView = webView else {
            isSubmitting = false
            loadingIndicator.stopAnimating()
            submitButton.setTitle("提交回复", for: .normal)
            showAlert(title: "错误", message: "无法提交回复")
            return
        }

        // Escape message for JavaScript
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let js = """
        (function() {
            var form = document.querySelector('form[name="reply"]') || document.querySelector('form');
            if (!form) {
                return {success: false, error: 'no_form'};
            }

            var messageField = form.querySelector('textarea[name="message"]') || form.querySelector('textarea');
            if (messageField) {
                messageField.value = '\(escapedMessage)';
            }

            // Submit form
            form.submit();
            return {success: true};
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[Reply] JS error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isSubmitting = false
                    self?.loadingIndicator.stopAnimating()
                    self?.submitButton.setTitle("提交回复", for: .normal)
                    self?.showAlert(title: "错误", message: "提交失败: \(error.localizedDescription)")
                }
                return
            }

            print("[Reply] Form submit JS executed successfully")
        }

        // Note: Rely on WKNavigationDelegate callbacks for result checking
        // Only use a fallback timeout in case navigation doesn't happen
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.isSubmitting else { return }
            print("[Reply] Fallback timeout reached, checking result...")
            self.checkSubmitResult()
        }
    }

    private func checkSubmitResult() {
        guard let webView = webView else { return }

        let url = webView.url?.absoluteString ?? ""
        print("[Reply] Checking submit result, URL: \(url)")

        // Success: navigated to viewthread page
        if url.contains("viewthread.php") && url.contains("tid=\(tid)") {
            print("[Reply] SUCCESS: Navigated to thread view")
            handleSubmitSuccess()
            return
        }

        // Check page content for success/error indicators
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
            guard let self = self else { return }

            if let text = result as? String {
                print("[Reply] Page text (first 200): \(String(text.prefix(200)))")

                // Check for success indicators
                let successIndicators = ["发帖成功", "回复成功", "succeed", "操作成功"]
                for indicator in successIndicators {
                    if text.contains(indicator) {
                        print("[Reply] SUCCESS: Found indicator: \(indicator)")
                        DispatchQueue.main.async {
                            self.handleSubmitSuccess()
                        }
                        return
                    }
                }

                // Check for error indicators
                let errorIndicators = ["错误", "失败", "error", "请登录", "验证码", "禁止", "不允许"]
                for indicator in errorIndicators {
                    if text.contains(indicator) {
                        print("[Reply] ERROR: Found indicator: \(indicator)")
                        DispatchQueue.main.async {
                            self.handleSubmitError("回复失败: \(indicator)")
                        }
                        return
                    }
                }
            }

            // If URL changed from reply page, assume success
            if !url.contains("post.php") && !url.contains("action=reply") {
                print("[Reply] SUCCESS: URL changed from reply page")
                DispatchQueue.main.async {
                    self.handleSubmitSuccess()
                }
            } else {
                print("[Reply] UNCERTAIN: Still on reply page or cannot determine")
                DispatchQueue.main.async {
                    self.handleSubmitError("无法确认回复是否成功，请手动检查")
                }
            }
        }
    }

    private func handleSubmitSuccess() {
        isSubmitting = false
        loadingIndicator.stopAnimating()
        delegate?.replyViewControllerDidPost(self)
        dismiss(animated: true)
    }

    private func handleSubmitError(_ message: String) {
        isSubmitting = false
        loadingIndicator.stopAnimating()
        submitButton.setTitle("提交回复", for: .normal)
        showAlert(title: "错误", message: message)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - WKNavigationDelegate

extension ReplyViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        print("[Reply] Page loaded: \(urlString)")

        // If submitting and reached thread view, it's success
        if isSubmitting && urlString.contains("viewthread.php") && urlString.contains("tid=\(tid)") {
            print("[Reply] SUCCESS: Thread view loaded after submit")
            handleSubmitSuccess()
            return
        }

        // If submitting, check for errors on current page
        if isSubmitting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkSubmitResult()
            }
            return
        }

        // Normal load - extract formhash from the page
        webView.evaluateJavaScript("document.querySelector('input[name=formhash]')?.value") { [weak self] result, error in
            guard let self = self else { return }

            if let hash = result as? String, !hash.isEmpty {
                print("[Reply] Found formhash: \(hash)")
                self.formhash = hash
            } else {
                // Try to extract from HTML
                webView.evaluateJavaScript("document.body.innerHTML") { [weak self] htmlResult, _ in
                    guard let html = htmlResult as? String else { return }

                    if let range = html.range(of: "formhash\" value=\"") {
                        let startIndex = range.upperBound
                        let endIndex = html.index(startIndex, offsetBy: 20, limitedBy: html.endIndex) ?? html.endIndex
                        let substring = String(html[startIndex..<endIndex])
                        if let hashEnd = substring.firstIndex(of: "\"") {
                            let hash = String(substring[..<hashEnd])
                            print("[Reply] Extracted formhash: \(hash)")
                            self?.formhash = hash
                        }
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Reply] Navigation failed: \(error.localizedDescription)")
        isSubmitting = false
        loadingIndicator.stopAnimating()
        submitButton.setTitle("提交回复", for: .normal)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
}
