import UIKit
import WebKit
import SDWebImage

class PMDetailViewController: UIViewController {

    private let uid: Int
    private let username: String

    private let tableView = UITableView()
    private let replyBar = UIView()
    private let replyTextView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var webView: WKWebView?
    private var messages: [PMMessage] = []
    private var formhash: String = ""

    init(uid: Int, username: String) {
        self.uid = uid
        self.username = username
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPMDetail()
    }

    private func setupUI() {
        title = "与 \(username) 的对话"
        view.backgroundColor = Theme.background

        setupReplyBar()
        setupTableView()
        setupLoadingIndicator()
    }

    private func setupReplyBar() {
        replyBar.backgroundColor = Theme.card
        replyBar.layer.borderColor = Theme.border.cgColor
        replyBar.layer.borderWidth = 0.5
        view.addSubview(replyBar)

        replyTextView.backgroundColor = Theme.background
        replyTextView.textColor = Theme.foreground
        replyTextView.font = .systemFont(ofSize: 15)
        replyTextView.layer.cornerRadius = 8
        replyTextView.layer.borderColor = Theme.border.cgColor
        replyTextView.layer.borderWidth = 0.5
        replyTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        replyTextView.isScrollEnabled = false
        replyTextView.delegate = self
        replyBar.addSubview(replyTextView)

        sendButton.setTitle("发送", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        sendButton.backgroundColor = Theme.primary
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.layer.cornerRadius = 8
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        replyBar.addSubview(sendButton)

        replyBar.translatesAutoresizingMaskIntoConstraints = false
        replyTextView.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            replyBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replyBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            replyBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            replyBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            replyTextView.leadingAnchor.constraint(equalTo: replyBar.leadingAnchor, constant: 12),
            replyTextView.topAnchor.constraint(equalTo: replyBar.topAnchor, constant: 8),
            replyTextView.bottomAnchor.constraint(equalTo: replyBar.bottomAnchor, constant: -8),
            replyTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            replyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            replyTextView.heightAnchor.constraint(lessThanOrEqualToConstant: 100),

            sendButton.trailingAnchor.constraint(equalTo: replyBar.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: replyBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 60),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PMMessageCell.self, forCellReuseIdentifier: PMMessageCell.identifier)
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: replyBar.topAnchor)
        ])
    }

    private func setupLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = Theme.primary
        view.addSubview(loadingIndicator)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadPMDetail() {
        loadingIndicator.startAnimating()

        // Create hidden WKWebView to handle Cloudflare
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = WebClientConfig.userAgent
        webView.navigationDelegate = self
        webView.isHidden = true
        self.webView = webView
        view.addSubview(webView)

        let pmURL = URL(string: "https://www.4d4y.com/forum/pm.php?uid=\(uid)&filter=privatepm&daterange=5")!
        webView.load(URLRequest(url: pmURL))

        print("[PMDetail] Loading PM page via WKWebView...")
    }

    private func extractPMContent() {
        guard let webView = webView else { return }

        let js = "document.documentElement.outerHTML"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[PMDetail] JS error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.loadingIndicator.stopAnimating()
                }
                return
            }

            guard let html = result as? String else {
                DispatchQueue.main.async {
                    self?.loadingIndicator.stopAnimating()
                }
                return
            }

            // Parse HTML using ForumHTMLParser
            do {
                if let data = html.data(using: .utf8) {
                    let detail = try ForumHTMLParser.parsePMDetail(data)
                    DispatchQueue.main.async {
                        self?.loadingIndicator.stopAnimating()
                        self?.messages = detail.messages
                        self?.formhash = detail.formhash ?? ""
                        self?.tableView.reloadData()
                        self?.scrollToBottom()
                    }
                } else {
                    // Try GB18030 encoding for Chinese websites
                    let gbEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
                    if let data = html.data(using: gbEncoding) {
                        let detail = try ForumHTMLParser.parsePMDetail(data)
                        DispatchQueue.main.async {
                            self?.loadingIndicator.stopAnimating()
                            self?.messages = detail.messages
                            self?.formhash = detail.formhash ?? ""
                            self?.tableView.reloadData()
                            self?.scrollToBottom()
                        }
                    }
                }
            } catch {
                print("[PMDetail] Parse error: \(error)")
                DispatchQueue.main.async {
                    self?.loadingIndicator.stopAnimating()
                }
            }
        }
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
    }

    @objc private func sendTapped() {
        guard webView != nil else { return }

        guard let message = replyTextView.text, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard !formhash.isEmpty else {
            showAlert(title: "提示", message: "正在加载表单数据，请稍后再试")
            return
        }

        sendButton.isEnabled = false

        sendReplyViaWebView(message: message)
    }

    private func sendReplyViaWebView(message: String) {
        guard let webView = webView else {
            sendButton.isEnabled = true
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
            var textarea = document.querySelector('#pmreplymessage') || document.querySelector('textarea[name="message"]');
            if (!textarea) {
                return {success: false, error: 'no_textarea'};
            }
            textarea.value = '\(escapedMessage)';

            var form = document.querySelector('#pmform') || document.querySelector('form');
            if (form) {
                form.submit();
                return {success: true};
            }
            return {success: false, error: 'no_form'};
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[PMDetail] Send JS error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.sendButton.isEnabled = true
                    self?.showAlert(title: "错误", message: "发送失败: \(error.localizedDescription)")
                }
                return
            }

            // Wait for message to be sent, then reload
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.replyTextView.text = ""
                self?.sendButton.isEnabled = true
                self?.loadPMDetail()
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension PMDetailViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PMMessageCell.identifier, for: indexPath) as? PMMessageCell else {
            return UITableViewCell()
        }
        let message = messages[indexPath.row]
        cell.configure(with: message)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - UITextViewDelegate

extension PMDetailViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        if size.height != textView.bounds.height {
            textView.isScrollEnabled = size.height > 100
        }
    }
}

// MARK: - WKNavigationDelegate

extension PMDetailViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        print("[PMDetail] Page loaded: \(urlString)")

        // Extract content after page finishes loading
        extractPMContent()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        print("[PMDetail] Load failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            self.showAlert(title: "错误", message: "加载失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - PM Message Cell

class PMMessageCell: UITableViewCell {

    static let identifier = "PMMessageCell"

    private let bubbleView = UIView()
    private let avatarImageView = UIImageView()
    private let authorLabel = UILabel()
    private let dateLabel = UILabel()
    private let contentLabel = UILabel()

    private var isSelfMessage = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        bubbleView.layer.cornerRadius = 12
        contentView.addSubview(bubbleView)

        avatarImageView.backgroundColor = Theme.muted
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 18
        avatarImageView.clipsToBounds = true
        avatarImageView.tintColor = Theme.secondaryText
        bubbleView.addSubview(avatarImageView)

        authorLabel.font = .systemFont(ofSize: 11)
        authorLabel.textColor = Theme.secondaryText
        bubbleView.addSubview(authorLabel)

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = Theme.secondaryText
        dateLabel.textAlignment = .right
        bubbleView.addSubview(dateLabel)

        contentLabel.font = .systemFont(ofSize: 14)
        contentLabel.numberOfLines = 0
        contentLabel.lineBreakMode = .byWordWrapping
        bubbleView.addSubview(contentLabel)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(with message: PMMessage) {
        self.isSelfMessage = message.isSelf

        authorLabel.text = message.author
        dateLabel.text = message.postDate
        contentLabel.text = message.content

        if let avatarURL = message.authorAvatar, !avatarURL.isEmpty {
            if avatarURL.hasPrefix("http") {
                avatarImageView.sd_setImage(with: URL(string: avatarURL), placeholderImage: UIImage(systemName: "person.circle.fill"))
            } else {
                avatarImageView.image = UIImage(systemName: "person.circle.fill")
            }
        } else {
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
        }

        updateConstraints(isSelf: message.isSelf)
        updateBubbleAppearance(isSelf: message.isSelf)
    }

    private func updateConstraints(isSelf: Bool) {
        NSLayoutConstraint.deactivate(bubbleView.constraints)

        if isSelf {
            NSLayoutConstraint.activate([
                bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60),
                bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

                avatarImageView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
                avatarImageView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
                avatarImageView.widthAnchor.constraint(equalToConstant: 36),
                avatarImageView.heightAnchor.constraint(equalToConstant: 36),

                dateLabel.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
                dateLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),

                authorLabel.trailingAnchor.constraint(equalTo: dateLabel.leadingAnchor, constant: -4),
                authorLabel.centerYAnchor.constraint(equalTo: dateLabel.centerYAnchor),

                contentLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 4),
                contentLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
                contentLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
                contentLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60),
                bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

                avatarImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
                avatarImageView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
                avatarImageView.widthAnchor.constraint(equalToConstant: 36),
                avatarImageView.heightAnchor.constraint(equalToConstant: 36),

                authorLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
                authorLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),

                dateLabel.leadingAnchor.constraint(equalTo: authorLabel.trailingAnchor, constant: 4),
                dateLabel.centerYAnchor.constraint(equalTo: authorLabel.centerYAnchor),

                contentLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 4),
                contentLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
                contentLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
                contentLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
            ])
        }
    }

    private func updateBubbleAppearance(isSelf: Bool) {
        if isSelf {
            bubbleView.backgroundColor = Theme.primary.withAlphaComponent(0.2)
            contentLabel.textColor = Theme.foreground
        } else {
            bubbleView.backgroundColor = Theme.card
            contentLabel.textColor = Theme.foreground
        }
    }
}
