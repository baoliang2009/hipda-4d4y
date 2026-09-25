import UIKit
import WebKit
import SDWebImage

class NotificationsViewController: UIViewController {

    private let tableView = UITableView()
    private let emptyView = UIView()
    private let emptyIconView = UIImageView()
    private let emptyLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var webView: WKWebView?
    private var privateMessages: [PrivateMessage] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPrivateMessages()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPrivateMessages()
    }

    private func setupUI() {
        title = "消息"
        view.backgroundColor = Theme.background

        setupTableView()
        setupEmptyState()
        setupLoadingIndicator()
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PMCell.self, forCellReuseIdentifier: PMCell.identifier)
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyView.isHidden = true
        view.addSubview(emptyView)

        emptyIconView.image = UIImage(systemName: "bell.slash")
        emptyIconView.tintColor = Theme.secondaryText
        emptyIconView.contentMode = .scaleAspectFit
        emptyView.addSubview(emptyIconView)

        emptyLabel.text = "暂无新消息"
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyView.addSubview(emptyLabel)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyIconView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            emptyIconView.topAnchor.constraint(equalTo: emptyView.topAnchor),
            emptyIconView.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyIconView.widthAnchor.constraint(equalToConstant: 80),
            emptyIconView.heightAnchor.constraint(equalToConstant: 80),

            emptyLabel.topAnchor.constraint(equalTo: emptyIconView.bottomAnchor, constant: 16),
            emptyLabel.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyView.bottomAnchor)
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

    private func loadPrivateMessages() {
        guard LoginManager.shared.isLoggedIn else {
            showEmptyState(message: "请先登录")
            return
        }

        loadingIndicator.startAnimating()
        emptyView.isHidden = true

        // 改走原生请求。
        // 之前用 WKWebView 取 outerHTML，再 `html.data(using: .utf8)` 交给
        // GB18030 优先的解析器——UTF-8 字节被当作 GB18030 解码，必定"成功"但全是乱码，
        // 私信列表因此永远解析不出来。原生请求拿到的是真正的 GBK 字节。
        print("[Notifications] Loading PM list natively...")

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let messages = try await NetworkManager.shared.fetchPrivateMessages()
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    print("[Notifications] Loaded \(messages.count) private messages")
                    self.privateMessages = messages
                    self.tableView.reloadData()
                    self.updateEmptyState()
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    print("[Notifications] Failed to load PMs: \(error.localizedDescription)")
                    self.updateEmptyState()
                }
            }
        }
    }

    private func extractPMList() {
        guard let webView = webView else { return }

        let js = "document.documentElement.outerHTML"
        webView.evaluateJavaScript(js) { [weak self] result, error in
            if let error = error {
                print("[Notifications] JS error: \(error.localizedDescription)")
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
                    let messages = try ForumHTMLParser.parsePrivateMessages(data)
                    DispatchQueue.main.async {
                        self?.loadingIndicator.stopAnimating()
                        self?.privateMessages = messages
                        self?.tableView.reloadData()
                        self?.updateEmptyState()
                    }
                } else {
                    // Try GB18030 encoding for Chinese websites
                    let gbEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
                    if let data = html.data(using: gbEncoding) {
                        let messages = try ForumHTMLParser.parsePrivateMessages(data)
                        DispatchQueue.main.async {
                            self?.loadingIndicator.stopAnimating()
                            self?.privateMessages = messages
                            self?.tableView.reloadData()
                            self?.updateEmptyState()
                        }
                    }
                }
            } catch {
                print("[Notifications] Parse error: \(error)")
                DispatchQueue.main.async {
                    self?.loadingIndicator.stopAnimating()
                    self?.showEmptyState(message: "加载失败")
                }
            }
        }
    }

    private func updateEmptyState() {
        if privateMessages.isEmpty {
            showEmptyState(message: "暂无新消息")
        } else {
            emptyView.isHidden = true
        }
    }

    private func showEmptyState(message: String) {
        emptyLabel.text = message
        emptyView.isHidden = false
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension NotificationsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return privateMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PMCell.identifier, for: indexPath) as? PMCell else {
            return UITableViewCell()
        }
        let pm = privateMessages[indexPath.row]
        cell.configure(with: pm)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pm = privateMessages[indexPath.row]
        let pmDetailVC = PMDetailViewController(uid: pm.fromUid, username: pm.fromUsername)
        navigationController?.pushViewController(pmDetailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - WKNavigationDelegate

extension NotificationsViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? ""
        print("[Notifications] Page loaded: \(urlString)")

        // Extract content after page finishes loading
        extractPMList()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        print("[Notifications] Load failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            self.showEmptyState(message: "加载失败")
        }
    }
}

// MARK: - PM Cell

class PMCell: UITableViewCell {

    static let identifier = "PMCell"

    private let containerView = UIView()
    private let avatarImageView = UIImageView()
    private let usernameLabel = UILabel()
    private let dateLabel = UILabel()
    private let subjectLabel = UILabel()
    private let summaryLabel = UILabel()
    private let newIndicator = UIView()

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

        containerView.backgroundColor = Theme.card
        containerView.layer.cornerRadius = 12
        contentView.addSubview(containerView)

        avatarImageView.backgroundColor = Theme.muted
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 24
        avatarImageView.clipsToBounds = true
        avatarImageView.tintColor = Theme.secondaryText
        containerView.addSubview(avatarImageView)

        usernameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        usernameLabel.textColor = Theme.titleText
        containerView.addSubview(usernameLabel)

        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = Theme.secondaryText
        dateLabel.textAlignment = .right
        containerView.addSubview(dateLabel)

        subjectLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subjectLabel.textColor = Theme.titleText
        subjectLabel.numberOfLines = 1
        containerView.addSubview(subjectLabel)

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = Theme.secondaryText
        summaryLabel.numberOfLines = 2
        containerView.addSubview(summaryLabel)

        newIndicator.backgroundColor = Theme.primary
        newIndicator.layer.cornerRadius = 4
        newIndicator.isHidden = true
        containerView.addSubview(newIndicator)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        subjectLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        newIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            avatarImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            avatarImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 48),
            avatarImageView.heightAnchor.constraint(equalToConstant: 48),

            usernameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),

            dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: usernameLabel.trailingAnchor, constant: 8),

            subjectLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4),
            subjectLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            subjectLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            summaryLabel.topAnchor.constraint(equalTo: subjectLabel.bottomAnchor, constant: 2),
            summaryLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            summaryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            newIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            newIndicator.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 4),
            newIndicator.widthAnchor.constraint(equalToConstant: 8),
            newIndicator.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    func configure(with pm: PrivateMessage) {
        usernameLabel.text = pm.fromUsername
        dateLabel.text = pm.messageDate
        subjectLabel.text = pm.subject
        summaryLabel.text = pm.summary
        newIndicator.isHidden = !pm.isNew

        if let avatarURL = pm.fromAvatar, !avatarURL.isEmpty {
            if avatarURL.hasPrefix("http") {
                avatarImageView.sd_setImage(with: URL(string: avatarURL), placeholderImage: UIImage(systemName: "person.circle.fill"))
            } else {
                avatarImageView.image = UIImage(systemName: "person.circle.fill")
            }
        } else {
            avatarImageView.image = UIImage(systemName: "person.circle.fill")
        }

        // Gray out if not new
        if pm.isNew {
            containerView.alpha = 1.0
        } else {
            containerView.alpha = 0.7
        }
    }
}
