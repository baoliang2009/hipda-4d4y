import UIKit

class SearchViewController: UIViewController {

    private let searchBar = UISearchBar()
    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var searchResults: [SearchResult] = []
    private var currentKeyword = ""
    private var currentPage = 1
    private var totalPages = 1
    private var isLoading = false
    private var lastErrorMessage: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = "搜索"
        view.backgroundColor = Theme.background

        setupSearchBar()
        setupTableView()
        setupEmptyLabel()
        setupLoadingIndicator()
    }

    private func setupSearchBar() {
        searchBar.placeholder = "搜索帖子标题"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.tintColor = Theme.primary
        searchBar.barTintColor = Theme.background
        view.addSubview(searchBar)

        if let textField = searchBar.value(forKey: "searchField") as? UITextField {
            textField.textColor = Theme.foreground
            textField.backgroundColor = Theme.card
        }

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        ])
    }

    private func setupTableView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.identifier)
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "输入关键词搜索帖子"
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = false
        view.addSubview(emptyLabel)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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

    private func performSearch(keyword: String) {
        guard !keyword.isEmpty, !isLoading else { return }

        currentKeyword = keyword
        currentPage = 1
        isLoading = true
        lastErrorMessage = nil

        loadingIndicator.startAnimating()
        emptyLabel.isHidden = true

        // 改走原生请求。
        // 之前用 WKWebView 取 outerHTML 再 `html.data(using: .utf8)` 交给
        // GB18030 优先的解析器 —— UTF-8 字节被当成 GB18030 解码，必定"成功"却全是乱码。
        // 且关键词需按 GBK 编码，由 NetworkManager.search 统一处理。
        print("[Search] Searching natively for: \(keyword)")

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let detail = try await NetworkManager.shared.search(keyword: keyword, page: 1)
                await MainActor.run {
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    print("[Search] Got \(detail.results.count) results (total \(detail.totalResults))")
                    self.searchResults = detail.results
                    self.currentPage = detail.currentPage
                    self.totalPages = detail.totalPages
                    self.tableView.reloadData()
                    self.updateEmptyState()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    let reason = (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
                    print("[Search] Failed: \(reason)")
                    // 失败不再静默：把真实原因显示出来，别和"无结果"混为一谈
                    self.searchResults = []
                    self.tableView.reloadData()
                    self.lastErrorMessage = reason
                    self.updateEmptyState()
                }
            }
        }
    }

    private func updateEmptyState() {
        if let err = lastErrorMessage {
            emptyLabel.text = "搜索失败：\(err)\n下拉关键词后重试"
            emptyLabel.isHidden = false
        } else if searchResults.isEmpty && !currentKeyword.isEmpty && !isLoading {
            emptyLabel.text = "未找到相关帖子"
            emptyLabel.isHidden = false
        } else if searchResults.isEmpty {
            emptyLabel.text = "输入关键词搜索帖子"
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }
}

// MARK: - UISearchBarDelegate

extension SearchViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        guard let keyword = searchBar.text, !keyword.isEmpty else { return }
        performSearch(keyword: keyword)
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.identifier, for: indexPath) as? SearchResultCell else {
            return UITableViewCell()
        }
        let result = searchResults[indexPath.row]
        print("[Search] cellForRowAt: \(indexPath.row), tid: \(result.tid), title: \(result.title)")
        cell.configure(with: result)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let result = searchResults[indexPath.row]

        // Debug logging
        print("[Search] Tapped result:")
        print("[Search]   tid: \(result.tid)")
        print("[Search]   title: \(result.title)")
        print("[Search]   forumName: \(result.forumName)")
        print("[Search]   forumFid: \(result.forumFid)")
        print("[Search]   author: \(result.author)")
        print("[Search]   authorUid: \(result.authorUid)")
        print("[Search]   replyCount: \(result.replyCount)")
        print("[Search]   viewCount: \(result.viewCount)")
        print("[Search]   lastPostAuthor: \(result.lastPostAuthor)")
        print("[Search]   lastPostDate: \(result.lastPostDate)")
        print("[Search]   viewthread URL: https://www.4d4y.com/forum/viewthread.php?tid=\(result.tid)")

        // Create a ForumThread from SearchResult
        let thread = ForumThread(
            tid: result.tid,
            title: result.title,
            author: result.author,
            authorUid: result.authorUid,
            replyCount: result.replyCount,
            viewCount: result.viewCount,
            lastPostDate: result.lastPostDate,
            lastPostAuthor: result.lastPostAuthor
        )
        let threadDetailVC = ThreadDetailViewController(thread: thread)
        navigationController?.pushViewController(threadDetailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 90
    }
}

// MARK: - Search Result Cell

class SearchResultCell: UITableViewCell {

    static let identifier = "SearchResultCell"

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let forumLabel = UILabel()
    private let authorLabel = UILabel()
    private let statsLabel = UILabel()
    private let lastPostLabel = UILabel()

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

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = Theme.titleText
        titleLabel.numberOfLines = 2
        containerView.addSubview(titleLabel)

        forumLabel.font = .systemFont(ofSize: 11)
        forumLabel.textColor = Theme.primary
        containerView.addSubview(forumLabel)

        authorLabel.font = .systemFont(ofSize: 12)
        authorLabel.textColor = Theme.secondaryText
        containerView.addSubview(authorLabel)

        statsLabel.font = .systemFont(ofSize: 11)
        statsLabel.textColor = Theme.secondaryText
        containerView.addSubview(statsLabel)

        lastPostLabel.font = .systemFont(ofSize: 11)
        lastPostLabel.textColor = Theme.secondaryText
        lastPostLabel.textAlignment = .right
        containerView.addSubview(lastPostLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        forumLabel.translatesAutoresizingMaskIntoConstraints = false
        authorLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        lastPostLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            forumLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            forumLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            authorLabel.centerYAnchor.constraint(equalTo: forumLabel.centerYAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: forumLabel.trailingAnchor, constant: 12),

            statsLabel.topAnchor.constraint(equalTo: forumLabel.bottomAnchor, constant: 6),
            statsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statsLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12),

            lastPostLabel.centerYAnchor.constraint(equalTo: statsLabel.centerYAnchor),
            lastPostLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12)
        ])
    }

    func configure(with result: SearchResult) {
        titleLabel.text = result.title
        forumLabel.text = result.forumName
        authorLabel.text = "作者: \(result.author)"
        statsLabel.text = "\(result.replyCount) 回复 · \(result.viewCount) 浏览"
        lastPostLabel.text = "\(result.lastPostAuthor)\n\(result.lastPostDate)"
        lastPostLabel.numberOfLines = 2
    }
}
