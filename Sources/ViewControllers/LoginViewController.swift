import UIKit
import WebKit

protocol LoginViewControllerDelegate: AnyObject {
    func loginViewControllerDidLogin(_ controller: LoginViewController)
    func loginViewControllerDidLoginWithForumData(_ controller: LoginViewController, forums: [Forum])
    func loginViewControllerDidCancel(_ controller: LoginViewController)
}

// MARK: - LoginViewController

class LoginViewController: UIViewController {

    weak var delegate: LoginViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let usernameTextField = UITextField()
    private let passwordTextField = UITextField()
    private let questionButton = UIButton(type: .system)
    private let answerTextField = UITextField()
    private let rememberMeSwitch = UISwitch()
    private let loginButton = UIButton(type: .system)

    private var selectedQuestionId = 0
    private let loginQuestions = [
        (id: 0, question: "安全提示问题"),
        (id: 1, question: "父亲出生的城市"),
        (id: 2, question: "母亲出生的城市"),
        (id: 3, question: "父亲工作的城市"),
        (id: 4, question: "心中最想念的地方"),
        (id: 5, question: "最爱的人的名字"),
        (id: 6, question: "最喜欢的食物"),
        (id: 7, question: "就读的第一所学校的名称")
    ]

    // MARK: - Loading Overlay

    private let loadingOverlay = UIView()
    private let loadingContainer = UIView()
    private let loadingSpinner = UIActivityIndicatorView(style: .large)
    private let loadingLabel = UILabel()
    private let loadingCancelButton = UIButton(type: .system)

    // MARK: - Login State

    private var webView: WKWebView?
    private var loginCompletion: ((Bool, String?) -> Void)?
    private var formhash: String?
    private var storedUsername: String = ""
    private var storedPassword: String = ""
    private var storedQuestionId: Int = 0
    private var storedAnswer: String = ""
    private var hasLoadedHomepage = false
    private var isLoggingIn = false
    private var loginStartTime: Date?

    // Timeout duration (60 seconds - increased for slow connections)
    private let loginTimeout: TimeInterval = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLoadingOverlay()
        loadSavedCredentials()
    }

    private func setupUI() {
        title = "登录"
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

        setupUsernameField()
        setupPasswordField()
        setupQuestionField()
        setupAnswerField()
        setupRememberMe()
        setupLoginButton()
    }

    private func setupLoadingOverlay() {
        loadingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        loadingOverlay.isHidden = true

        loadingContainer.backgroundColor = Theme.card
        loadingContainer.layer.cornerRadius = 16
        loadingContainer.layer.borderColor = Theme.border.cgColor
        loadingContainer.layer.borderWidth = 1

        loadingSpinner.color = Theme.primary

        loadingLabel.text = "正在连接服务器..."
        loadingLabel.font = .systemFont(ofSize: 16, weight: .medium)
        loadingLabel.textColor = Theme.foreground
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 0

        loadingCancelButton.setTitle("取消", for: .normal)
        loadingCancelButton.setTitleColor(Theme.primary, for: .normal)
        loadingCancelButton.titleLabel?.font = .systemFont(ofSize: 15)
        loadingCancelButton.addTarget(self, action: #selector(cancelLoginTapped), for: .touchUpInside)

        view.addSubview(loadingOverlay)
        loadingOverlay.addSubview(loadingContainer)
        loadingContainer.addSubview(loadingSpinner)
        loadingContainer.addSubview(loadingLabel)
        loadingContainer.addSubview(loadingCancelButton)

        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingCancelButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingContainer.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingContainer.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
            loadingContainer.widthAnchor.constraint(equalToConstant: 240),

            loadingSpinner.topAnchor.constraint(equalTo: loadingContainer.topAnchor, constant: 30),
            loadingSpinner.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),

            loadingLabel.topAnchor.constraint(equalTo: loadingSpinner.bottomAnchor, constant: 20),
            loadingLabel.leadingAnchor.constraint(equalTo: loadingContainer.leadingAnchor, constant: 20),
            loadingLabel.trailingAnchor.constraint(equalTo: loadingContainer.trailingAnchor, constant: -20),

            loadingCancelButton.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 20),
            loadingCancelButton.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            loadingCancelButton.bottomAnchor.constraint(equalTo: loadingContainer.bottomAnchor, constant: -20)
        ])
    }

    private func showLoading(message: String) {
        loadingLabel.text = message
        loadingSpinner.startAnimating()
        loadingOverlay.isHidden = false
        loginButton.isEnabled = false
    }

    private func updateLoadingMessage(_ message: String) {
        loadingLabel.text = message
    }

    private func hideLoading() {
        loadingOverlay.isHidden = true
        loadingSpinner.stopAnimating()
        loginButton.isEnabled = true
    }

    private func setupUsernameField() {
        let label = UILabel()
        label.text = "用户名"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        usernameTextField.borderStyle = .roundedRect
        usernameTextField.autocapitalizationType = .none
        usernameTextField.autocorrectionType = .no
        usernameTextField.placeholder = "输入用户名"
        usernameTextField.backgroundColor = Theme.muted
        usernameTextField.textColor = Theme.foreground

        contentView.addSubview(label)
        contentView.addSubview(usernameTextField)

        label.translatesAutoresizingMaskIntoConstraints = false
        usernameTextField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            usernameTextField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            usernameTextField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            usernameTextField.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            usernameTextField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupPasswordField() {
        let label = UILabel()
        label.text = "密码"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        passwordTextField.borderStyle = .roundedRect
        passwordTextField.isSecureTextEntry = true
        passwordTextField.placeholder = "输入密码"
        passwordTextField.backgroundColor = Theme.muted
        passwordTextField.textColor = Theme.foreground

        contentView.addSubview(label)
        contentView.addSubview(passwordTextField)

        label.translatesAutoresizingMaskIntoConstraints = false
        passwordTextField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: usernameTextField.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            passwordTextField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            passwordTextField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            passwordTextField.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            passwordTextField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupQuestionField() {
        let label = UILabel()
        label.text = "安全问题"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        questionButton.setTitle(loginQuestions[0].question, for: .normal)
        questionButton.contentHorizontalAlignment = .left
        questionButton.titleLabel?.font = .systemFont(ofSize: 16)
        questionButton.tintColor = Theme.foreground
        questionButton.layer.borderWidth = 1
        questionButton.layer.borderColor = Theme.border.cgColor
        questionButton.layer.cornerRadius = 5
        questionButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        questionButton.addTarget(self, action: #selector(selectQuestion), for: .touchUpInside)

        contentView.addSubview(label)
        contentView.addSubview(questionButton)

        label.translatesAutoresizingMaskIntoConstraints = false
        questionButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: passwordTextField.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            questionButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            questionButton.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            questionButton.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            questionButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupAnswerField() {
        let label = UILabel()
        label.text = "安全问题答案"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        answerTextField.borderStyle = .roundedRect
        answerTextField.placeholder = "输入答案"
        answerTextField.autocapitalizationType = .none
        answerTextField.autocorrectionType = .no
        answerTextField.backgroundColor = Theme.muted
        answerTextField.textColor = Theme.foreground

        contentView.addSubview(label)
        contentView.addSubview(answerTextField)

        label.translatesAutoresizingMaskIntoConstraints = false
        answerTextField.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: questionButton.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            answerTextField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            answerTextField.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            answerTextField.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            answerTextField.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupRememberMe() {
        let label = UILabel()
        label.text = "记住登录"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Theme.secondaryText

        rememberMeSwitch.isOn = true
        rememberMeSwitch.onTintColor = Theme.primary

        contentView.addSubview(label)
        contentView.addSubview(rememberMeSwitch)

        label.translatesAutoresizingMaskIntoConstraints = false
        rememberMeSwitch.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: answerTextField.bottomAnchor, constant: 20),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            rememberMeSwitch.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            rememberMeSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    private func setupLoginButton() {
        loginButton.setTitle("登录", for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        loginButton.backgroundColor = Theme.primary
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.layer.cornerRadius = 8
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        contentView.addSubview(loginButton)

        loginButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: rememberMeSwitch.bottomAnchor, constant: 30),
            loginButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            loginButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            loginButton.heightAnchor.constraint(equalToConstant: 50),
            loginButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func loadSavedCredentials() {
        if let username = LoginManager.shared.username {
            usernameTextField.text = username
        }
        if let password = LoginManager.shared.password {
            passwordTextField.text = password
        }
        selectedQuestionId = LoginManager.shared.questionId
        questionButton.setTitle(loginQuestions.first { $0.id == selectedQuestionId }?.question ?? "安全提示问题", for: .normal)
        answerTextField.text = LoginManager.shared.answer
    }

    @objc private func cancelTapped() {
        delegate?.loginViewControllerDidCancel(self)
        dismiss(animated: true)
    }

    @objc private func cancelLoginTapped() {
        cancelLogin()
        hideLoading()
        loginButton.setTitle("登录", for: .normal)
    }

    @objc private func selectQuestion() {
        let alert = UIAlertController(title: "选择安全问题", message: nil, preferredStyle: .actionSheet)

        for question in loginQuestions {
            alert.addAction(UIAlertAction(title: question.question, style: .default) { [weak self] _ in
                self?.selectedQuestionId = question.id
                self?.questionButton.setTitle(question.question, for: .normal)
            })
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = questionButton
            popover.sourceRect = questionButton.bounds
        }

        present(alert, animated: true)
    }

    @objc private func loginTapped() {
        guard let username = usernameTextField.text, !username.isEmpty,
              let password = passwordTextField.text, !password.isEmpty else {
            showAlert(title: "错误", message: "请输入用户名和密码")
            return
        }

        let answer = answerTextField.text ?? ""

        loginButton.isEnabled = false
        loginButton.setTitle("登录中...", for: .normal)

        // Show loading overlay with status
        showLoading(message: "正在登录...")

        // 优先走原生登录。
        // Cloudflare 只拦 WKWebView（Turnstile 过不去），URLSession 反而是通的，
        // 所以原生是主路径；只有原生也失败时才退回 WebView 兜底。
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let result = try await NetworkManager.shared.nativeLogin(
                    username: username,
                    password: password,
                    questionId: self.selectedQuestionId,
                    answer: answer
                )

                await MainActor.run {
                    LoginManager.shared.applySuccessfulLogin(
                        result: result,
                        password: password,
                        answer: answer
                    )
                    self.finishSuccessfulLogin()
                }
            } catch {
                let message = (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
                print("[Login] Native login failed: \(message), falling back to WebView")

                await MainActor.run {
                    self.updateLoadingMessage("正在尝试网页登录...")
                    self.fallbackToWebViewLogin(
                        username: username,
                        password: password,
                        answer: answer,
                        nativeError: message
                    )
                }
            }
        }
    }

    /// 原生登录失败后的兜底：仍然用原来的 WKWebView 流程走一遍
    private func fallbackToWebViewLogin(username: String, password: String, answer: String, nativeError: String) {
        loginWithWebView(
            username: username,
            password: password,
            questionId: selectedQuestionId,
            answer: answer
        ) { [weak self] success, errorMessage in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if success {
                    if self.rememberMeSwitch.isOn {
                        LoginManager.shared.saveCredentials(
                            username: username,
                            password: password,
                            questionId: self.selectedQuestionId,
                            answer: answer
                        )
                    }
                    LoginManager.shared.isLoggedIn = true
                    self.finishSuccessfulLogin()
                } else {
                    self.hideLoading()
                    self.loginButton.isEnabled = true
                    self.loginButton.setTitle("登录", for: .normal)
                    // 两条路都失败时，报原生那条的原因——它通常才是真正的失败原因
                    // （比如密码错误），WebView 那条多半只是卡在 Cloudflare 验证上
                    self.showAlert(title: "登录失败", message: nativeError.isEmpty ? (errorMessage ?? "登录失败") : nativeError)
                }
            }
        }
    }

    /// 登录成功后的界面收尾
    private func finishSuccessfulLogin() {
        hideLoading()
        loginButton.isEnabled = true
        loginButton.setTitle("登录", for: .normal)

        // Clear forum list cache so it refreshes with logged-in data
        CacheManager.shared.clearCache(forKey: CacheManager.CacheKeys.forumList())
        print("[Login] Cleared forum list cache after successful login")

        delegate?.loginViewControllerDidLogin(self)
        dismiss(animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Cancel Login

    private var loginTimeoutTimer: Timer?

    private func cancelLogin() {
        loginTimeoutTimer?.invalidate()
        loginTimeoutTimer = nil
        isLoggingIn = false

        // Cancel any pending webview loads
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func startLoginTimeoutTimer() {
        loginTimeoutTimer?.invalidate()
        loginTimeoutTimer = Timer.scheduledTimer(withTimeInterval: loginTimeout, repeats: false) { [weak self] _ in
            self?.handleLoginTimeout()
        }
    }

    private func handleLoginTimeout() {
        print("[Login] Login timeout after \(loginTimeout) seconds")
        cancelLogin()

        DispatchQueue.main.async { [weak self] in
            self?.hideLoading()
            self?.loginButton.isEnabled = true
            self?.loginButton.setTitle("登录", for: .normal)
            self?.showAlert(title: "登录超时", message: "连接服务器超时，请检查网络后重试")
        }
    }

    // MARK: - WKWebView Login

    private var forumListCompletion: (([Forum]) -> Void)?
    private var webViewLoadStartTime: Date?

    private func loginWithWebView(
        username: String,
        password: String,
        questionId: Int,
        answer: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        self.loginCompletion = completion
        self.storedUsername = username
        self.storedPassword = password
        self.storedQuestionId = questionId
        self.storedAnswer = answer
        self.loginStartTime = Date()
        self.isLoggingIn = false  // Don't set to true yet - wait until we have formhash

        // Create visible WebView for better stability on real devices
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        // Enable JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        // Use desktop Chrome user agent for proper forum parsing
        // 必须和 NetworkManager 用同一个 UA：cf_clearance 就是在这个 WebView 里拿到的，
        // UA 不一致会让同步给 URLSession 的 clearance 直接失效
        webView.customUserAgent = WebClientConfig.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.frame = view.bounds
        webView.isHidden = false  // Make visible so user can complete Cloudflare challenge
        webView.alpha = 0  // Start transparent, will fade in if challenge appears
        self.webView = webView
        self.webViewLoadStartTime = Date()
        view.addSubview(webView)

        // Store for later use
        self.formhash = nil

        // Start timeout timer
        startLoginTimeoutTimer()

        // Set forumListCompletion before performLogin so it's ready when we redirect to index.php
        self.forumListCompletion = { _ in }
        self.hasLoadedHomepage = false

        // First load forum homepage to establish session and get past Cloudflare
        updateLoadingMessage("正在连接服务器...")
        let homeURL = URL(string: "https://www.4d4y.com/forum/")!
        webView.load(URLRequest(url: homeURL))

        print("[Login] Loading homepage first to bypass Cloudflare...")
    }

    private func performLogin() {
        guard let webView = webView, let formhash = self.formhash else {
            print("[Login] Cannot perform login: webView=\(webView != nil), formhash=\(self.formhash ?? "nil")")
            loginCompletion?(false, "无法获取表单hash")
            return
        }

        let username = storedUsername
        let password = storedPassword
        let questionId = storedQuestionId
        let answer = storedAnswer
        let passwordMD5 = password.md5

        print("[Login] Performing login with formhash: \(formhash)")
        print("[Login] Login parameters - username: \(username), passwordMD5: \(passwordMD5), questionId: \(questionId), answer: \(answer)")

        // Extract sid from current URL if present
        let currentURL = webView.url?.absoluteString ?? ""
        print("[Login] Current URL: \(currentURL)")
        var sidParam = ""
        if let sidRange = currentURL.range(of: "sid=([^&]+)", options: .regularExpression) {
            let sid = String(currentURL[sidRange]).replacingOccurrences(of: "sid=", with: "")
            sidParam = "&sid=" + sid
            print("[Login] Found sid parameter: \(sid)")
        } else {
            print("[Login] No sid parameter found in URL")
        }

        updateLoadingMessage("正在验证用户信息...")

        // JavaScript to submit login form via AJAX
        let js = #"""
        (function() {
            var xhr = new XMLHttpRequest();
            xhr.open('POST', 'https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes&inajax=1\#(sidParam)', true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
            xhr.setRequestHeader('Origin', 'https://www.4d4y.com');
            xhr.setRequestHeader('Referer', 'https://www.4d4y.com/forum/logging.php?action=login');
            xhr.withCredentials = true;
            xhr.onload = function() {
                console.log('Login XHR completed, status:', xhr.status, 'responseURL:', xhr.responseURL);
                var response = xhr.responseText || '';
                console.log('Login XHR response length:', response.length);
                console.log('Login XHR response (first 500 chars):', response.substring(0, 500));

                // Check Set-Cookie headers in response
                var setCookieHeader = xhr.getResponseHeader('Set-Cookie');
                console.log('Set-Cookie header:', setCookieHeader);

                // Check if login succeeded - Discuz returns specific patterns
                var loginSuccess = response.includes('succeedhandle') ||
                                   response.includes('登录成功') ||
                                   response.includes('location.href') ||
                                   (xhr.status >= 200 && xhr.status < 300);
                console.log('Login success check:', loginSuccess);

                // Wait a bit for cookies to be set before redirecting
                setTimeout(function() {
                    console.log('Redirecting to forum homepage...');
                    window.location.href = 'https://www.4d4y.com/forum/';
                }, 1000);
            };
            xhr.onerror = function() {
                console.log('Login XHR error, status:', xhr.status);
                setTimeout(function() {
                    window.location.href = 'https://www.4d4y.com/forum/';
                }, 1000);
            };
            xhr.onloadstart = function() {
                console.log('Login XHR started');
            };
            xhr.ontimeout = function() {
                console.log('Login XHR timeout');
            };
            var params = 'formhash=' + encodeURIComponent('\#(formhash)') +
                '&referer=' + encodeURIComponent('https://www.4d4y.com/forum/') +
                '&loginfield=username' +
                '&username=' + encodeURIComponent('\#(username)') +
                '&password=' + encodeURIComponent('\#(passwordMD5)') +
                '&questionid=' + encodeURIComponent('\#(questionId)') +
                '&answer=' + encodeURIComponent('\#(answer)') +
                '&cookietime=2592000';
            console.log('Sending login request with params:', params);
            xhr.send(params);
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[Login] JS error: \(error.localizedDescription)")
            }
            print("[Login] Login JS executed")
        }
    }

    private func syncCookiesToSharedStorage(from webView: WKWebView, completion: @escaping (Bool) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            print("[CookieSync] WKWebView cookies count: \(cookies.count)")
            for cookie in cookies {
                print("[CookieSync] WKCookie: \(cookie.name)=\(cookie.value.prefix(30))... domain=\(cookie.domain) path=\(cookie.path)")
            }

            let storage = HTTPCookieStorage.shared
            for cookie in cookies {
                // Only sync cookies for 4d4y.com domain
                if cookie.domain.contains("4d4y.com") {
                    if let existingCookie = storage.cookies?.first(where: { $0.name == cookie.name }) {
                        storage.deleteCookie(existingCookie)
                    }
                    storage.setCookie(cookie)
                    print("[CookieSync] Synced: \(cookie.name) = \(cookie.value.prefix(20))...")
                }
            }
            print("[CookieSync] Total cookies synced to shared: \(cookies.count)")

            // Check for required login cookies in the original cookies
            let hasAuth = cookies.contains { $0.name == "cdb_auth" }
            let hasSid = cookies.contains { $0.name == "cdb_sid" }
            print("[CookieSync] Has cdb_auth: \(hasAuth), Has cdb_sid: \(hasSid)")

            // Now also save cookies to LoginManager for persistence
            LoginManager.shared.saveCookies()

            completion(hasAuth && hasSid)
        }
    }

    /// Parse forum list HTML to extract Forum objects
    private func parseForumListHTML(_ html: String) -> [Forum]? {
        var forums: [Forum] = []

        // Pattern to match forum links with fid
        let pattern = "href=\"[^\"]*?fid=(\\d+)[^\"]*?\"[^>]*?>([^<]+)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            if let fidRange = Range(match.range(at: 1), in: html),
               let nameRange = Range(match.range(at: 2), in: html),
               let fid = Int(html[fidRange]) {
                let name = String(html[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty && name.count < 100 {
                    let forum = Forum(fid: fid, name: name, description: "", threadCount: 0, postCount: 0)
                    forums.append(forum)
                }
            }
        }

        // Remove duplicates by fid
        var uniqueForums: [Forum] = []
        var seenFids = Set<Int>()
        for forum in forums {
            if !seenFids.contains(forum.fid) {
                seenFids.insert(forum.fid)
                uniqueForums.append(forum)
            }
        }

        return uniqueForums
    }

    private func cleanup() {
        loginTimeoutTimer?.invalidate()
        loginTimeoutTimer = nil

        // Immediately cleanup webView
        if let webView = self.webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.removeFromSuperview()
        }
        self.webView = nil
    }

    // MARK: - Cloudflare Challenge Helpers

    /// 页面状态。判定逻辑见 `ForumPageProbe`（与 CloudflareManager 共用同一份，
    /// 避免两处各自维护、各自漂移）。
    typealias PageState = ForumPageProbe.State

    private func evaluatePageState(webView: WKWebView, completion: @escaping (PageState) -> Void) {
        webView.evaluateJavaScript(ForumPageProbe.javaScript) { result, error in
            if result == nil, let error = error {
                print("[Login] Page state JS error: \(error.localizedDescription)")
            }
            completion(ForumPageProbe.parse(result))
        }
    }

    /// 把验证页交给用户操作。
    ///
    /// Turnstile 可能需要用户点一下复选框，这期间必须：
    /// 1. 把 WebView 显示出来并允许交互
    /// 2. **暂停全局登录超时**——否则 60 秒一到 `handleLoginTimeout` 会把 WebView
    ///    直接拆掉，用户正在验证也照拆不误
    private func beginUserChallenge(on webView: WKWebView, message: String) {
        updateLoadingMessage(message)

        loginTimeoutTimer?.invalidate()
        loginTimeoutTimer = nil

        UIView.animate(withDuration: 0.3) {
            webView.alpha = 1.0
        }
        webView.isUserInteractionEnabled = true
        loadingOverlay.isHidden = true
    }

    /// 验证结束，收回 WebView 并恢复全局超时
    private func endUserChallenge(on webView: WKWebView, message: String) {
        UIView.animate(withDuration: 0.3) {
            webView.alpha = 0
        }
        loadingOverlay.isHidden = false
        updateLoadingMessage(message)

        startLoginTimeoutTimer()
    }

    /// 轮询等待 Cloudflare 验证通过。
    ///
    /// 以"真正的 Discuz 页面是否出现"为通过条件（正向判定），
    /// 1 秒一次、最长等 `timeout` 秒。Turnstile 通过后 Cloudflare 会自行刷新页面，
    /// 所以这里只需要安静地等它变成真实页面即可。
    ///
    /// - Parameter timeout: 默认给到 180 秒。验证页此时是显示给用户的，
    ///   需要人去点复选框、读提示，45 秒根本不够；而且全局超时已经在
    ///   `beginUserChallenge` 里暂停了，这里是唯一的兜底。
    private func waitForCloudflareChallenge(webView: WKWebView,
                                            retryCount: Int,
                                            timeout: TimeInterval = 180,
                                            completion: @escaping (Bool) -> Void) {
        let pollInterval: TimeInterval = 1.0
        let maxAttempts = Int(timeout / pollInterval)

        if retryCount >= maxAttempts {
            print("[Login] Cloudflare challenge timeout after \(Int(timeout)) seconds")
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            guard let self = self, self.webView != nil else {
                completion(false)
                return
            }

            self.evaluatePageState(webView: webView) { [weak self] state in
                guard let self = self else {
                    completion(false)
                    return
                }

                // 通过条件：不再是拦截页，且真实的 Discuz 页面已经加载出来
                if !state.isChallenge && state.isDiscuzPage {
                    print("[Login] Cloudflare challenge passed (discuz page is live)")
                    completion(true)
                    return
                }

                if retryCount % 5 == 0 {
                    print("[Login] Waiting for Cloudflare... \(retryCount)/\(maxAttempts) (challenge=\(state.isChallenge), discuz=\(state.isDiscuzPage))")
                }
                self.waitForCloudflareChallenge(webView: webView,
                                                retryCount: retryCount + 1,
                                                timeout: timeout,
                                                completion: completion)
            }
        }
    }

    private func navigateToLoginPage(webView: WKWebView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let loginURL = URL(string: "https://www.4d4y.com/forum/logging.php?action=login")!
            var request = URLRequest(url: loginURL)
            request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
            webView.load(request)
            print("[Login] Loading login page after homepage...")
        }
    }

    private func syncCookiesAndComplete(webView: WKWebView) {
        syncCookiesToSharedStorage(from: webView) { [weak self] hasCookies in
            guard let self = self else { return }
            print("[Login] Cookie sync result: hasCookies=\(hasCookies)")

            // Save cookies to UserDefaults for persistence
            if hasCookies {
                LoginManager.shared.saveCookies()
                print("[Login] Saved cookies to UserDefaults for persistence")
            }

            if self.forumListCompletion != nil {
                self.extractForumListHTML(from: webView)
            } else {
                // No forum list completion, just notify login success
                print("[Login] Login completed, notifying delegate")
                self.delegate?.loginViewControllerDidLogin(self)
                self.cleanup()
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension LoginViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        let elapsed = Date().timeIntervalSince(loginStartTime ?? Date())
        print("[Login] Page loaded [\(String(format: "%.1f", elapsed))s]: \(urlString)")

        // Check if this is the homepage (first load to establish session and bypass Cloudflare)
        if !hasLoadedHomepage && (urlString.contains("/forum/") || urlString.contains("4d4y.com/forum")) && !urlString.contains("logging.php") {
            print("[Login] Homepage loaded successfully, checking for Cloudflare challenge...")
            hasLoadedHomepage = true

            // Check if we're on a Cloudflare challenge page
            evaluatePageState(webView: webView) { [weak self] state in
                guard let self = self else { return }

                if state.isChallenge || !state.isDiscuzPage {
                    print("[Login] Cloudflare challenge detected on homepage, showing WebView for user interaction...")
                    self.beginUserChallenge(on: webView, message: "请完成安全验证")

                    // Wait for Turnstile to complete, checking periodically
                    self.waitForCloudflareChallenge(webView: webView, retryCount: 0) { success in
                        if success {
                            print("[Login] Cloudflare challenge passed, now navigating to login page...")
                            // Hide WebView again
                            self.endUserChallenge(on: webView, message: "正在加载登录页面...")
                            self.navigateToLoginPage(webView: webView)
                        } else {
                            print("[Login] Cloudflare challenge failed to complete")
                            self.loginCompletion?(false, "安全验证超时，请重试")
                            self.cleanup()
                        }
                    }
                    return
                }

                // No challenge, proceed to login page
                print("[Login] No challenge detected, navigating to login page...")
                self.updateLoadingMessage("正在加载登录页面...")

                // Wait a bit for cookies to be set, then navigate to login
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.navigateToLoginPage(webView: webView)
                }
            }
            return
        }

        // Check if this is the memcp.php page (for UID extraction)
        if urlString.contains("memcp.php") {
            print("[Login] Detected memcp.php page, extracting UID...")
            updateLoadingMessage("正在获取用户信息...")
            extractUIDFromMemcp(webView: webView)
            return
        }

        // Check if this is the forum index page (being loaded after login success)
        if hasLoadedHomepage && isLoggingIn && (urlString.contains("forum/index.php") || urlString.contains("/index.php") || (urlString.contains("/forum/") && !urlString.contains("logging.php"))) {
            print("[Login] Detected forum page after login attempt, checking for Cloudflare challenge...")

            // Check if we're on a Cloudflare challenge page again
            evaluatePageState(webView: webView) { [weak self] state in
                guard let self = self else { return }

                if state.isChallenge || !state.isDiscuzPage {
                    print("[Login] Cloudflare challenge detected after login, showing WebView...")
                    self.beginUserChallenge(on: webView, message: "请再次完成安全验证")

                    // Wait for challenge to complete
                    self.waitForCloudflareChallenge(webView: webView, retryCount: 0) { success in
                        if success {
                            print("[Login] Post-login Cloudflare challenge passed, syncing cookies...")
                            self.endUserChallenge(on: webView, message: "正在同步登录状态...")
                            self.syncCookiesAndComplete(webView: webView)
                        } else {
                            print("[Login] Post-login Cloudflare challenge failed")
                            self.loginCompletion?(false, "登录后验证失败，请重试")
                            self.cleanup()
                        }
                    }
                    return
                }

                // No challenge, proceed with normal login completion
                print("[Login] No challenge after login, syncing cookies...")
                self.updateLoadingMessage("正在同步登录状态...")
                self.syncCookiesAndComplete(webView: webView)
            }
            return
        }

        // Only check for logged in status on the login page itself (after homepage was loaded)
        if hasLoadedHomepage && urlString.contains("logging.php") && !isLoggingIn {
            // Wait a moment for page to fully render
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, let webView = self.webView else { return }

                self.evaluatePageState(webView: webView) { [weak self] state in
                    guard let self = self else { return }

                    // 仍在 Cloudflare 拦截页（或真实页面尚未就绪）：把 WebView 显示出来，
                    // 让用户可以点验证码，然后轮询等它过
                    if state.isChallenge || !state.isDiscuzPage {
                        print("[Login] Cloudflare challenge detected on login page, showing WebView...")
                        self.beginUserChallenge(on: webView, message: "请完成安全验证")

                        self.waitForCloudflareChallenge(webView: webView, retryCount: 0) { success in
                            guard success else {
                                print("[Login] Login page Cloudflare challenge failed")
                                self.loginCompletion?(false, "验证失败，请重试")
                                self.cleanup()
                                return
                            }

                            print("[Login] Login page Cloudflare challenge passed, continuing login flow...")
                            self.endUserChallenge(on: webView, message: "正在准备登录...")

                            // 验证通过后 Cloudflare 会自行刷新回登录页，
                            // 这里直接继续走取 formhash → 提交的流程
                            self.proceedWithLoginPage(webView: webView, attempt: 0)
                        }
                        return
                    }

                    self.proceedWithLoginPage(webView: webView, attempt: 0)
                }
            }
        }
    }

    /// 登录页已就绪后：判断是否已登录，否则取 formhash 并提交。
    ///
    /// formhash 可能因为页面还在渲染而暂时取不到，这里带重试（每次间隔 1.5 秒）。
    private func proceedWithLoginPage(webView: WKWebView, attempt: Int) {
        let maxAttempts = 4

        evaluatePageState(webView: webView) { [weak self] state in
            guard let self = self else { return }

            // 已经是登录状态（discuz_uid > 0 是最可靠的判据，
            // 不要去匹配「欢迎」之类的文案，更不能硬编码某个用户名）
            if state.uid > 0 {
                print("[Login] Already logged in (uid=\(state.uid)), syncing cookies...")
                self.handleLoginSuccess(webView: webView)
                return
            }

            if !state.formhash.isEmpty {
                print("[Login] Found formhash: \(state.formhash)")
                self.formhash = state.formhash
                self.isLoggingIn = true
                self.performLogin()
                return
            }

            guard attempt < maxAttempts else {
                print("[Login] Could not find formhash after \(maxAttempts) attempts")
                self.loginCompletion?(false, "无法获取登录表单，请稍后重试")
                self.cleanup()
                return
            }

            print("[Login] formhash not ready, retrying \(attempt + 1)/\(maxAttempts)... (challenge=\(state.isChallenge), discuz=\(state.isDiscuzPage), loginForm=\(state.hasLoginForm))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, let webView = self.webView else { return }
                self.proceedWithLoginPage(webView: webView, attempt: attempt + 1)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Login] Navigation failed: \(error.localizedDescription)")

        let nsError = error as NSError
        if nsError.code != NSURLErrorCancelled {
            loginCompletion?(false, error.localizedDescription)
            cleanup()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[Login] Provisional navigation failed: \(error.localizedDescription)")

        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            print("[Login] Cancelled provisional navigation (redirect), waiting...")
            return
        }

        if error.localizedDescription.contains("cancelled") {
            print("[Login] May be Cloudflare challenge, waiting...")
            return
        }

        loginCompletion?(false, error.localizedDescription)
        cleanup()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            print("[Login] Response: \(response.statusCode) - \(response.url?.absoluteString ?? "nil")")

            // Handle 403 (Cloudflare challenge)
            if response.statusCode == 403 {
                print("[Login] Got 403, allowing to proceed for Cloudflare challenge handling")
                updateLoadingMessage("正在通过安全验证...")
            }
        }
        decisionHandler(.allow)
    }

    private func handleLoginSuccess(webView: WKWebView) {
        updateLoadingMessage("登录成功，正在同步数据...")
        syncCookiesToSharedStorage(from: webView) { [weak self] hasCookies in
            guard let self = self else { return }

            print("[Login] After cookie sync - hasCookies: \(hasCookies)")

            if hasCookies {
                // Save cookies to UserDefaults for persistence
                LoginManager.shared.saveCookies()
                print("[Login] Saved cookies after login success")

                // First go to memcp.php to extract UID
                print("[Login] Proceeding to memcp.php to get UID...")
                let memcpURL = URL(string: "https://www.4d4y.com/forum/memcp.php")!
                webView.load(URLRequest(url: memcpURL))
            } else {
                self.loginCompletion?(false, "登录失败，未获取到有效的会话")
                self.cleanup()
            }
        }
    }

    private func extractUIDFromMemcp(webView: WKWebView) {
        webView.evaluateJavaScript("document.body.innerHTML") { [weak self] bodyResult, bodyError in
            guard let self = self else { return }

            if let bodyHtml = bodyResult as? String {
                print("[Login] memcp.php body HTML length: \(bodyHtml.count)")
            }

            let js = #"""
            (function() {
                var umenu = document.getElementById('umenu');
                if (!umenu) {
                    var allLinks = document.querySelectorAll('a[href*="uid="]');
                    for (var i = 0; i < allLinks.length; i++) {
                        var href = allLinks[i].getAttribute('href');
                        var match = href.match(/uid=(\d+)/);
                        if (match && match[1]) {
                            return match[1];
                        }
                    }
                    return null;
                }

                var links = umenu.querySelectorAll('a[href*="space.php?uid="]');
                for (var i = 0; i < links.length; i++) {
                    var href = links[i].getAttribute('href');
                    var match = href.match(/uid=(\d+)/);
                    if (match && match[1]) {
                        return match[1];
                    }
                }
                return null;
            })();
            """#

            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self = self else { return }

                print("[Login] UID extraction result: \(result ?? "nil")")

                if let uidStr = result as? String, let uid = Int(uidStr) {
                    print("[Login] Extracted UID: \(uid)")
                    LoginManager.shared.uid = uid

                    // Extract username from the page
                    self.extractUsernameAndCreateAccount(webView: webView, uid: uid)
                } else {
                    print("[Login] Failed to extract UID, proceeding anyway")
                    self.proceedToForumPage(webView: webView)
                }
            }
        }
    }

    private func proceedToForumPage(webView: WKWebView) {
        print("[Login] Proceeding to forum page...")
        self.forumListCompletion = { _ in }
        let forumURL = URL(string: "https://www.4d4y.com/forum/index.php")!
        webView.load(URLRequest(url: forumURL))
    }

    private func extractUsernameAndCreateAccount(webView: WKWebView, uid: Int) {
        let js = #"""
        (function() {
            // Try to find username from various locations
            // 1. Try from umenu
            var umenu = document.getElementById('umenu');
            if (umenu) {
                var links = umenu.querySelectorAll('a');
                for (var i = 0; i < links.length; i++) {
                    var text = links[i].textContent.trim();
                    if (text && text.length > 0 && text !== '个人中心' && text !== '短消息') {
                        return text;
                    }
                }
            }

            // 2. Try from space.php link text
            var spaceLinks = document.querySelectorAll('a[href*="space.php"]');
            for (var i = 0; i < spaceLinks.length; i++) {
                var text = spaceLinks[i].textContent.trim();
                if (text && text.length > 0 && !text.includes('空间') && !text.includes('UID')) {
                    return text;
                }
            }

            // 3. Try from any element containing "欢迎"
            var welcomeText = document.body.textContent || document.body.innerText;
            var match = welcomeText.match(/欢迎[,，\s]*([^\s,，。！]+)/);
            if (match && match[1]) {
                return match[1];
            }

            return null;
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            let username: String
            if let extractedUsername = result as? String, !extractedUsername.isEmpty {
                print("[Login] Extracted username: \(extractedUsername)")
                username = extractedUsername
            } else {
                // Fallback to stored username from text field
                username = self.storedUsername ?? "User_\(uid)"
                print("[Login] Could not extract username from page, using: \(username)")
            }

            // Save to LoginManager for backward compatibility
            LoginManager.shared.username = username

            // Create or update account in AccountManager
            let password = self.storedPassword ?? ""
            let questionId = self.storedQuestionId ?? 0
            let answer = self.storedAnswer ?? ""

            print("[Login] Creating account - username: \(username), uid: \(uid)")
            // preserveCurrentCookies: 这里还在登录流程中途，HTTPCookieStorage.shared
            // 里正是刚登录拿到的活 Cookie。若走默认路径，saveAccount 内部的
            // switchToAccount 会先 clearAllCookies() 再用该账号的旧快照（新账号则为空）
            // 恢复，等于当场把登录态清空。
            let account = AccountManager.shared.saveAccount(
                username: username,
                password: password,
                uid: uid,
                questionId: questionId,
                answer: answer,
                preserveCurrentCookies: true
            )

            // Save cookies to this account
            AccountManager.shared.saveCookies(for: account)
            print("[Login] Account created and activated with ID: \(account.id)")

            // Proceed to forum page
            self.proceedToForumPage(webView: webView)
        }
    }

    private func extractForumListHTML(from webView: WKWebView) {
        let js = #"""
        (function() {
            var forumTable = document.querySelector('table.forumlist') || document.querySelector('.forumlist');
            if (forumTable) {
                return forumTable.innerHTML;
            }
            var lists = document.querySelectorAll('.fl_ul, .forumlist, #forumlist');
            for (var i = 0; i < lists.length; i++) {
                if (lists[i].innerHTML.includes('fid=') || lists[i].innerHTML.includes('forumdisplay')) {
                    return lists[i].innerHTML;
                }
            }
            return document.body.innerHTML;
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let html = result as? String {
                print("[Login] Extracted forum HTML length: \(html.count)")

                if let forums = self.parseForumListHTML(html) {
                    print("[Login] Parsed \(forums.count) forums from HTML")

                    LoginManager.shared.saveCookies()

                    self.forumListCompletion?(forums)
                    self.delegate?.loginViewControllerDidLoginWithForumData(self, forums: forums)
                    self.loginCompletion?(true, nil)
                    self.cleanup()
                } else {
                    print("[Login] Failed to parse forum HTML")
                    self.loginCompletion?(false, "无法解析论坛数据")
                    self.cleanup()
                }
            } else {
                print("[Login] Failed to extract forum HTML: \(error?.localizedDescription ?? "unknown")")
                self.loginCompletion?(false, error?.localizedDescription ?? "获取论坛列表失败")
                self.cleanup()
            }
        }
    }
}

// MARK: - WKUIDelegate

extension LoginViewController: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewConfigurationFor navigationAction: WKNavigationAction) -> WKWebViewConfiguration {
        return WKWebViewConfiguration()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        print("[Login] JS Alert: \(message)")
        completionHandler()
    }
}
