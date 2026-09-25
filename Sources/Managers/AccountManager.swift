import Foundation

/// 多账号管理器
class AccountManager {
    static let shared = AccountManager()

    private let accountsKey = "saved_accounts"
    private let activeAccountIdKey = "active_account_id"

    private var accounts: [Account] = []
    private var activeAccountId: String?

    private init() {
        loadAccounts()
    }

    // MARK: - Active Account

    /// 当前激活的账号
    var activeAccount: Account? {
        guard let id = activeAccountId else { return nil }
        return accounts.first { $0.id == id }
    }

    /// 切换到指定账号
    ///
    /// - Parameter applyingStoredCookies: 是否用该账号保存的 Cookie 快照覆盖当前的
    ///   `HTTPCookieStorage.shared`。用户主动切号时需要（true，默认）；
    ///   但**刚登录完成时必须传 false** —— 此时内存里的才是刚拿到的、完整的登录
    ///   Cookie（含 `cdb_auth` 和 Cloudflare 的 `cf_clearance`），
    ///   而"清空 + 从快照重建"是有损的（`HTTPCookie(properties:)` 无法还原
    ///   HttpOnly / SameSite 等属性），会把刚登录成功的会话打坏。
    @discardableResult
    func switchToAccount(_ account: Account, applyingStoredCookies: Bool = true) -> Bool {
        guard accounts.contains(where: { $0.id == account.id }) else {
            print("[AccountManager] Account not found: \(account.username)")
            return false
        }

        // 真正的切号才需要先把当前账号的 Cookie 落盘（否则切走后它的会话就丢了）。
        // 登录路径下当前内存里的 Cookie 属于「正在登录的这个账号」，
        // 若写进上一个账号会造成串号，所以只在 applyingStoredCookies 时做。
        if applyingStoredCookies, let current = activeAccount, current.id != account.id {
            saveCookies(for: current)
        }

        // 更新激活状态
        for index in accounts.indices {
            accounts[index].isActive = (accounts[index].id == account.id)
            if accounts[index].id == account.id {
                accounts[index].lastLoginDate = Date()
            }
        }

        activeAccountId = account.id
        saveAccounts()

        // 应用账号的 Cookie
        if applyingStoredCookies {
            restoreCookies(for: account)
        } else {
            print("[AccountManager] Keeping live cookies for: \(account.username)")
        }

        print("[AccountManager] Switched to account: \(account.username)")
        return true
    }

    // MARK: - Account Management

    /// 添加或更新账号
    ///
    /// - Parameter preserveCurrentCookies: 传 true 表示"当前 `HTTPCookieStorage.shared`
    ///   里就是这个账号刚登录拿到的 Cookie"，此时不要用旧快照去覆盖它，
    ///   而是反过来把这份活 Cookie 存为该账号的新快照。登录成功后必须传 true。
    @discardableResult
    func saveAccount(username: String, password: String, uid: Int, questionId: Int, answer: String, preserveCurrentCookies: Bool = false) -> Account {
        // 查找已存在的账号：优先用 uid 匹配。
        // 登录流程中会先用「页面解析出的用户名」建账号，随后 saveCredentials 又会用
        // 「用户输入的用户名」再调一次；两者大小写/昵称不一致时只靠用户名匹配会建出
        // 重复账号（且第二个 uid=0）。uid 才是论坛侧的唯一标识。
        var existingIndex: Int? = nil
        if uid > 0 {
            existingIndex = accounts.firstIndex(where: { $0.uid == uid })
        }
        if existingIndex == nil {
            existingIndex = accounts.firstIndex(where: { $0.username == username })
        }

        if let existingIndex = existingIndex {
            // 更新现有账号
            var account = accounts[existingIndex]
            account.lastLoginDate = Date()
            // uid 是登录后才解析出来的，拿到有效值时要回填，否则多账号会一直是 0
            if uid > 0 {
                account.uid = uid
            }
            account.questionId = questionId
            accounts[existingIndex] = account

            // 更新密码和答案
            _ = KeychainManager.shared.save(password, forKey: account.passwordKey)
            _ = KeychainManager.shared.save(answer, forKey: account.answerKey)

            print("[AccountManager] Updated existing account: \(username)")

            switchToAccount(account, applyingStoredCookies: !preserveCurrentCookies)

            // 切换完再落盘，确保这份活 Cookie 记在正确的账号名下
            if preserveCurrentCookies {
                saveCookies(for: account)
            }
            return account
        } else {
            // 创建新账号
            let newAccount = Account(username: username, uid: uid, questionId: questionId)

            // 保存密码和答案到 Keychain
            _ = KeychainManager.shared.save(password, forKey: newAccount.passwordKey)
            _ = KeychainManager.shared.save(answer, forKey: newAccount.answerKey)

            // 添加到列表
            accounts.append(newAccount)

            print("[AccountManager] Added new account: \(username)")

            switchToAccount(newAccount, applyingStoredCookies: !preserveCurrentCookies)

            if preserveCurrentCookies {
                saveCookies(for: newAccount)
            }
            return newAccount
        }
    }

    /// 删除账号
    func deleteAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        // 删除 Keychain 中的数据
        _ = KeychainManager.shared.delete(forKey: account.passwordKey)
        _ = KeychainManager.shared.delete(forKey: account.answerKey)

        // 删除 Cookie
        UserDefaults.standard.removeObject(forKey: account.cookiesKey)

        // 从列表中移除
        accounts.remove(at: index)

        // 如果删除的是当前账号，切换到第一个账号或清空
        if account.id == activeAccountId {
            if let firstAccount = accounts.first {
                _ = switchToAccount(firstAccount)
            } else {
                activeAccountId = nil
                clearAllCookies()
            }
        }

        saveAccounts()
        print("[AccountManager] Deleted account: \(account.username)")
    }

    /// 获取所有账号
    func getAllAccounts() -> [Account] {
        return accounts.sorted { $0.lastLoginDate > $1.lastLoginDate }
    }

    /// 获取账号数量
    var accountCount: Int {
        return accounts.count
    }

    /// 获取账号的密码
    func getPassword(for account: Account) -> String? {
        return KeychainManager.shared.load(forKey: account.passwordKey)
    }

    /// 获取账号的安全问题答案
    func getAnswer(for account: Account) -> String? {
        return KeychainManager.shared.load(forKey: account.answerKey)
    }

    // MARK: - Cookie Management

    /// 保存当前账号的 Cookie
    func saveCookies(for account: Account) {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }

        let cookieData = cookies.compactMap { cookie -> [String: Any]? in
            // Only save cookies for 4d4y.com domain
            guard cookie.domain.contains("4d4y.com") else { return nil }

            var properties: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
                "secure": cookie.isSecure,
                "httpOnly": cookie.isHTTPOnly
            ]

            // Save expiration date if available
            if let expiresDate = cookie.expiresDate {
                properties["expires"] = expiresDate.timeIntervalSince1970
            }

            properties["version"] = cookie.version

            return properties
        }

        UserDefaults.standard.set(cookieData, forKey: account.cookiesKey)
        print("[AccountManager] Saved \(cookieData.count) cookies for account: \(account.username)")
    }

    /// 恢复账号的 Cookie
    func restoreCookies(for account: Account) {
        // 先清空当前所有 Cookie
        clearAllCookies()

        guard let cookieData = UserDefaults.standard.array(forKey: account.cookiesKey) as? [[String: Any]] else {
            print("[AccountManager] No saved cookies for account: \(account.username), key: \(account.cookiesKey)")
            return
        }

        print("[AccountManager] Found \(cookieData.count) cookies to restore for account: \(account.username)")

        let storage = HTTPCookieStorage.shared
        var restoredCount = 0

        for data in cookieData {
            guard let name = data["name"] as? String,
                  let value = data["value"] as? String,
                  let domain = data["domain"] as? String,
                  let path = data["path"] as? String else {
                continue
            }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]

            if let secure = data["secure"] as? Bool, secure {
                properties[.secure] = "TRUE"
            }

            if let expiresTimestamp = data["expires"] as? TimeInterval {
                let expiresDate = Date(timeIntervalSince1970: expiresTimestamp)
                if expiresDate > Date() {
                    properties[.expires] = expiresDate
                } else {
                    print("[AccountManager] Skipping expired cookie: \(name)")
                    continue
                }
            }

            if let version = data["version"] as? Int {
                properties[.version] = version
            }

            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
                restoredCount += 1
            }
        }

        print("[AccountManager] Restored \(restoredCount)/\(cookieData.count) cookies for account: \(account.username)")
    }

    /// 清空所有 Cookie
    private func clearAllCookies() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("4d4y.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    // MARK: - Persistence

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            print("[AccountManager] No saved accounts found")
            migrateFromLegacy()
            return
        }

        do {
            accounts = try JSONDecoder().decode([Account].self, from: data)
            activeAccountId = UserDefaults.standard.string(forKey: activeAccountIdKey)

            print("[AccountManager] Loaded \(accounts.count) accounts")
            print("[AccountManager] Active account ID: \(activeAccountId ?? "nil")")

            // 如果有激活的账号，恢复其 Cookie
            if let active = activeAccount {
                print("[AccountManager] Restoring cookies for active account: \(active.username)")
                restoreCookies(for: active)
            } else {
                print("[AccountManager] No active account found")
                // 如果没有激活账号但有账号列表，自动激活第一个
                if let firstAccount = accounts.first {
                    print("[AccountManager] Auto-activating first account: \(firstAccount.username)")
                    _ = switchToAccount(firstAccount)
                }
            }
        } catch {
            print("[AccountManager] Failed to load accounts: \(error)")
            accounts = []
        }
    }

    private func saveAccounts() {
        do {
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: accountsKey)

            if let id = activeAccountId {
                UserDefaults.standard.set(id, forKey: activeAccountIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeAccountIdKey)
            }

            print("[AccountManager] Saved \(accounts.count) accounts")
        } catch {
            print("[AccountManager] Failed to save accounts: \(error)")
        }
    }

    // MARK: - Migration from Legacy LoginManager

    /// 从旧的 LoginManager 迁移数据
    private func migrateFromLegacy() {
        // 检查是否有旧的登录数据
        guard let username = UserDefaults.standard.string(forKey: "forum_username"),
              !username.isEmpty else {
            return
        }

        print("[AccountManager] Migrating legacy account data...")

        // 获取旧数据
        let uid = UserDefaults.standard.integer(forKey: "forum_uid")
        let questionId = UserDefaults.standard.integer(forKey: "forum_question_id")
        let password = KeychainManager.shared.load(forKey: "forum_password_secure") ?? ""
        let answer = KeychainManager.shared.load(forKey: "forum_answer_secure") ?? ""

        // 创建账号
        let account = saveAccount(
            username: username,
            password: password,
            uid: uid,
            questionId: questionId,
            answer: answer
        )

        // 迁移 Cookie
        if let legacyCookies = UserDefaults.standard.array(forKey: "forum_cookies") as? [[String: Any]] {
            UserDefaults.standard.set(legacyCookies, forKey: account.cookiesKey)
            restoreCookies(for: account)
        }

        print("[AccountManager] Migration completed for account: \(username)")
    }

    // MARK: - Logout

    /// 退出当前账号（不删除）
    func logout() {
        if let account = activeAccount {
            saveCookies(for: account)
        }

        activeAccountId = nil
        clearAllCookies()
        UserDefaults.standard.removeObject(forKey: activeAccountIdKey)

        print("[AccountManager] Logged out")
    }
}
