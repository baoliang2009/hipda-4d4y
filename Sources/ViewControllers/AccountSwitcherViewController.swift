import UIKit

protocol AccountSwitcherDelegate: AnyObject {
    func accountSwitcherDidSwitchAccount(_ controller: AccountSwitcherViewController)
    func accountSwitcherDidAddAccount(_ controller: AccountSwitcherViewController)
}

class AccountSwitcherViewController: UIViewController {

    weak var delegate: AccountSwitcherDelegate?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var accounts: [Account] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAccounts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAccounts()
    }

    private func setupUI() {
        title = "账号管理"
        view.backgroundColor = Theme.background

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = Theme.primary

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addAccountTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = Theme.primary

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AccountCell.self, forCellReuseIdentifier: "AccountCell")
        tableView.backgroundColor = Theme.background
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadAccounts() {
        accounts = AccountManager.shared.getAllAccounts()
        tableView.reloadData()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func addAccountTapped() {
        let loginVC = LoginViewController()
        loginVC.delegate = self
        let navVC = UINavigationController(rootViewController: loginVC)
        present(navVC, animated: true)
    }

    private func switchToAccount(_ account: Account) {
        let success = AccountManager.shared.switchToAccount(account)

        if success {
            // 更新 LoginManager 的兼容性接口
            LoginManager.shared.isLoggedIn = true

            showAlert(title: "切换成功", message: "已切换到账号: \(account.username)") { [weak self] in
                guard let self = self else { return }
                self.loadAccounts()
                self.delegate?.accountSwitcherDidSwitchAccount(self)
                self.dismiss(animated: true)
            }
        } else {
            showAlert(title: "切换失败", message: "无法切换到该账号")
        }
    }

    private func deleteAccount(_ account: Account) {
        let alert = UIAlertController(
            title: "删除账号",
            message: "确定要删除账号 \(account.username) 吗？\n\n此操作将删除该账号的所有本地数据（包括密码和登录状态）。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            AccountManager.shared.deleteAccount(account)
            self?.loadAccounts()

            // 如果删除后没有账号了，更新 LoginManager
            if AccountManager.shared.accountCount == 0 {
                LoginManager.shared.isLoggedIn = false
            }
        })

        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension AccountSwitcherViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return accounts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as! AccountCell
        let account = accounts[indexPath.row]
        let isActive = AccountManager.shared.activeAccount?.id == account.id
        cell.configure(with: account, isActive: isActive)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let account = accounts[indexPath.row]

        // 如果是当前账号，不需要切换
        if AccountManager.shared.activeAccount?.id == account.id {
            return
        }

        // 切换账号
        switchToAccount(account)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let account = accounts[indexPath.row]

        let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            self?.deleteAccount(account)
            completion(true)
        }
        deleteAction.backgroundColor = .systemRed

        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return accounts.isEmpty ? nil : "已保存的账号"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if accounts.isEmpty {
            return "还没有保存的账号\n点击右上角 + 添加账号"
        } else {
            return "点击账号切换，左滑删除账号"
        }
    }
}

// MARK: - LoginViewControllerDelegate

extension AccountSwitcherViewController: LoginViewControllerDelegate {
    func loginViewControllerDidLogin(_ controller: LoginViewController) {
        // 登录成功，重新加载账号列表
        loadAccounts()
        delegate?.accountSwitcherDidAddAccount(self)
    }

    func loginViewControllerDidLoginWithForumData(_ controller: LoginViewController, forums: [Forum]) {
        loadAccounts()
        delegate?.accountSwitcherDidAddAccount(self)
    }

    func loginViewControllerDidCancel(_ controller: LoginViewController) {
        // 取消登录
    }
}

// MARK: - AccountCell

class AccountCell: UITableViewCell {

    private let avatarView = UIView()
    private let avatarLabel = UILabel()
    private let usernameLabel = UILabel()
    private let uidLabel = UILabel()
    private let lastLoginLabel = UILabel()
    private let activeIndicator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = Theme.card
        selectionStyle = .default

        // Avatar
        avatarView.backgroundColor = Theme.primary.withAlphaComponent(0.2)
        avatarView.layer.cornerRadius = 25
        avatarView.clipsToBounds = true
        contentView.addSubview(avatarView)

        avatarLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        avatarLabel.textColor = Theme.primary
        avatarLabel.textAlignment = .center
        avatarView.addSubview(avatarLabel)

        // Username
        usernameLabel.font = .systemFont(ofSize: 16, weight: .medium)
        usernameLabel.textColor = Theme.foreground
        contentView.addSubview(usernameLabel)

        // UID
        uidLabel.font = .systemFont(ofSize: 13)
        uidLabel.textColor = Theme.secondaryText
        contentView.addSubview(uidLabel)

        // Last login
        lastLoginLabel.font = .systemFont(ofSize: 12)
        lastLoginLabel.textColor = Theme.secondaryText
        contentView.addSubview(lastLoginLabel)

        // Active indicator
        activeIndicator.backgroundColor = Theme.primary
        activeIndicator.layer.cornerRadius = 4
        activeIndicator.isHidden = true
        contentView.addSubview(activeIndicator)

        // Layout
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        uidLabel.translatesAutoresizingMaskIntoConstraints = false
        lastLoginLabel.translatesAutoresizingMaskIntoConstraints = false
        activeIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 50),
            avatarView.heightAnchor.constraint(equalToConstant: 50),

            avatarLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            avatarLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),

            usernameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            usernameLabel.trailingAnchor.constraint(equalTo: activeIndicator.leadingAnchor, constant: -8),

            uidLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 4),
            uidLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor),
            uidLabel.trailingAnchor.constraint(equalTo: usernameLabel.trailingAnchor),

            lastLoginLabel.topAnchor.constraint(equalTo: uidLabel.bottomAnchor, constant: 2),
            lastLoginLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor),
            lastLoginLabel.trailingAnchor.constraint(equalTo: usernameLabel.trailingAnchor),

            activeIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            activeIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            activeIndicator.widthAnchor.constraint(equalToConstant: 8),
            activeIndicator.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    func configure(with account: Account, isActive: Bool) {
        // Avatar - show first character of username
        let firstChar = account.username.prefix(1).uppercased()
        avatarLabel.text = firstChar

        usernameLabel.text = account.username
        uidLabel.text = "UID: \(account.uid)"

        // Format last login date
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        let timeString = formatter.localizedString(for: account.lastLoginDate, relativeTo: Date())
        lastLoginLabel.text = "上次登录: \(timeString)"

        // Show active indicator
        activeIndicator.isHidden = !isActive

        if isActive {
            usernameLabel.textColor = Theme.primary
        } else {
            usernameLabel.textColor = Theme.foreground
        }
    }
}
