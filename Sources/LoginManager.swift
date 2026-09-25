import Foundation

class LoginManager {
    static let shared = LoginManager()

    private let usernameKey = "forum_username"
    private let passwordKey = "forum_password_secure"
    private let questionIdKey = "forum_question_id"
    private let answerKey = "forum_answer_secure"
    private let isLoggedInKey = "forum_is_logged_in"
    private let loginDateKey = "forum_login_date"
    private let cookiesKey = "forum_cookies"
    private let uidKey = "forum_uid"

    private init() {
        // Restore cookies on startup
        restoreCookies()
        // Migrate old credentials if needed
        migrateOldCredentials()
    }

    var username: String? {
        get { UserDefaults.standard.string(forKey: usernameKey) }
        set { UserDefaults.standard.set(newValue, forKey: usernameKey) }
    }

    var uid: Int {
        get { UserDefaults.standard.integer(forKey: uidKey) }
        set { UserDefaults.standard.set(newValue, forKey: uidKey) }
    }

    var password: String? {
        get { KeychainManager.shared.load(forKey: passwordKey) }
        set {
            if let value = newValue {
                _ = KeychainManager.shared.save(value, forKey: passwordKey)
            } else {
                _ = KeychainManager.shared.delete(forKey: passwordKey)
            }
        }
    }

    var questionId: Int {
        get { UserDefaults.standard.integer(forKey: questionIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: questionIdKey) }
    }

    var answer: String? {
        get { KeychainManager.shared.load(forKey: answerKey) }
        set {
            if let value = newValue {
                _ = KeychainManager.shared.save(value, forKey: answerKey)
            } else {
                _ = KeychainManager.shared.delete(forKey: answerKey)
            }
        }
    }

    var isLoggedIn: Bool {
        get {
            // 优先检查 AccountManager 中是否有激活账号
            if AccountManager.shared.activeAccount != nil {
                return true
            }

            // 否则检查旧的登录状态（向后兼容）
            let loggedIn = UserDefaults.standard.bool(forKey: isLoggedInKey)
            if loggedIn {
                refreshLoginState()
            }
            return loggedIn
        }
        set { UserDefaults.standard.set(newValue, forKey: isLoggedInKey) }
    }

    /// 获取当前账号信息（多账号支持）
    var currentAccount: Account? {
        return AccountManager.shared.activeAccount
    }

    /// 获取当前用户名（兼容旧代码）
    var currentUsername: String? {
        return currentAccount?.username ?? username
    }

    /// 获取当前 UID（兼容旧代码）
    var currentUid: Int {
        return currentAccount?.uid ?? uid
    }

    private var loginDate: Date? {
        get { UserDefaults.standard.object(forKey: loginDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: loginDateKey) }
    }

    func saveCredentials(username: String, password: String, questionId: Int, answer: String, uid: Int = 0) {
        // uid 是登录流程中从 memcp.php 解析出来后写进 self.uid 的，
        // 调用方通常不带 uid 参数，这里不能用 0 把它冲掉
        let resolvedUid = uid > 0 ? uid : self.uid

        self.username = username
        self.password = password
        self.questionId = questionId
        self.answer = answer
        self.uid = resolvedUid
        self.loginDate = Date()

        // 同时保存到 AccountManager。
        // preserveCurrentCookies: 此刻 HTTPCookieStorage.shared 里是刚登录拿到的
        // 活 Cookie，必须保留它并以它为准落盘，不能被账号里的旧快照覆盖。
        AccountManager.shared.saveAccount(
            username: username,
            password: password,
            uid: resolvedUid,
            questionId: questionId,
            answer: answer,
            preserveCurrentCookies: true
        )
    }

    func clearCredentials() {
        // 使用 AccountManager 的退出功能
        AccountManager.shared.logout()

        // 清理旧的兼容数据
        username = nil
        password = nil
        questionId = 0
        answer = nil
        uid = 0
        isLoggedIn = false
        loginDate = nil
        clearCookies()

        // Also clear old UserDefaults keys if they exist
        UserDefaults.standard.removeObject(forKey: "forum_password")
        UserDefaults.standard.removeObject(forKey: "forum_answer")
    }

    // MARK: - Migration

    /// Migrate old plaintext credentials to Keychain
    private func migrateOldCredentials() {
        // Migrate password
        if let oldPassword = UserDefaults.standard.string(forKey: "forum_password") {
            print("[LoginManager] Migrating password to Keychain")
            password = oldPassword
            UserDefaults.standard.removeObject(forKey: "forum_password")
        }

        // Migrate answer
        if let oldAnswer = UserDefaults.standard.string(forKey: "forum_answer") {
            print("[LoginManager] Migrating answer to Keychain")
            answer = oldAnswer
            UserDefaults.standard.removeObject(forKey: "forum_answer")
        }
    }

    private func refreshLoginState() {
        guard let date = loginDate else {
            isLoggedIn = false
            return
        }
        let interval = Date().timeIntervalSince(date)
        if interval > 7 * 24 * 60 * 60 {
            isLoggedIn = false
        }
    }

    // MARK: - Cookie Persistence

    /// Save current cookies to UserDefaults with enhanced attributes
    func saveCookies() {
        // 如果有激活账号，保存到该账号
        if let activeAccount = AccountManager.shared.activeAccount {
            AccountManager.shared.saveCookies(for: activeAccount)
            return
        }

        // 否则使用旧的保存方式（向后兼容）
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

            // Save version
            properties["version"] = cookie.version

            return properties
        }

        UserDefaults.standard.set(cookieData, forKey: cookiesKey)
        print("[LoginManager] Saved \(cookieData.count) cookies with full attributes")
    }

    /// Restore cookies from UserDefaults with enhanced attributes
    func restoreCookies() {
        // 如果 AccountManager 有激活账号，它会自动恢复 Cookie
        if AccountManager.shared.activeAccount != nil {
            print("[LoginManager] Skipping cookie restore - AccountManager handles it")
            return
        }

        guard let cookieData = UserDefaults.standard.array(forKey: cookiesKey) as? [[String: Any]] else {
            print("[LoginManager] No saved cookies found in UserDefaults key: \(cookiesKey)")
            return
        }

        print("[LoginManager] Found \(cookieData.count) cookies to restore from legacy storage")

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

            // Restore secure flag
            if let secure = data["secure"] as? Bool, secure {
                properties[.secure] = "TRUE"
            }

            // Restore expiration date and check if expired
            if let expiresTimestamp = data["expires"] as? TimeInterval {
                let expiresDate = Date(timeIntervalSince1970: expiresTimestamp)
                // Only restore non-expired cookies
                if expiresDate > Date() {
                    properties[.expires] = expiresDate
                } else {
                    print("[LoginManager] Skipping expired cookie: \(name)")
                    continue
                }
            }

            // Restore version
            if let version = data["version"] as? Int {
                properties[.version] = version
            }

            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
                restoredCount += 1
                print("[LoginManager] Restored cookie: \(name)")
            }
        }

        print("[LoginManager] Restored \(restoredCount)/\(cookieData.count) cookies")
    }

    /// Clear saved cookies
    func clearCookies() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        UserDefaults.standard.removeObject(forKey: cookiesKey)
    }

    /// Check if cookies exist and are valid
    func hasValidCookies() -> Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return false }

        let hasAuth = cookies.contains { $0.name == "cdb_auth" }
        let hasSid = cookies.contains { $0.name == "cdb_sid" }

        return hasAuth && hasSid
    }
    
    func getLoginJavaScript() -> String? {
        guard let username = username,
              let password = password else {
            return nil
        }
        
        let questionId = self.questionId
        let answer = self.answer ?? ""
        
        return """
        (function() {
            try {
                var form = document.getElementById('loginform');
                if (!form) return {success: false, error: 'no_form'};
                
                var usernameField = form.querySelector('input[name="username"]');
                var passwordField = document.getElementById('password3');
                var questionSelect = document.getElementById('questionid');
                var answerField = document.getElementById('answer');
                var cookietime = document.getElementById('cookietime');
                
                if (usernameField) usernameField.value = '\(username.escapedForJavaScript)';
                if (passwordField) passwordField.value = '\(password.escapedForJavaScript)';
                if (questionSelect) questionSelect.value = '\(questionId)';
                if (answerField) answerField.value = '\(answer.escapedForJavaScript)';
                if (cookietime) cookietime.checked = true;
                
                if (typeof hex_md5 === 'function' && passwordField) {
                    passwordField.value = hex_md5(passwordField.value);
                }
                
                return {success: true, needsMD5: typeof hex_md5 !== 'function'};
            } catch(e) {
                console.error('Login fill error:', e);
                return {success: false, error: e.message};
            }
        })();
        """
    }
    
    func getSubmitLoginJavaScript() -> String {
        return """
        (function() {
            try {
                var form = document.getElementById('loginform');
                if (!form) return {status: 'no_form'};
                
                var passwordField = document.getElementById('password3');
                if (passwordField && passwordField.value && passwordField.value.length !== 32) {
                    if (typeof hex_md5 === 'function') {
                        passwordField.value = hex_md5(passwordField.value);
                    }
                }
                
                form.submit();
                return {status: 'submitted'};
            } catch(e) {
                return {status: 'error', message: e.message};
            }
        })();
        """
    }
    
    func getCheckLoginStatusJavaScript() -> String {
        return """
        (function() {
            try {
                var umenu = document.getElementById('umenu');
                if (!umenu) return {loggedIn: false, reason: 'no_umenu'};
                
                var loginLink = umenu.querySelector('a[href*="login"]');
                var registerLink = umenu.querySelector('a[href*="tobenew"]');
                var usernameLinks = umenu.querySelectorAll('a[href*="space"]');
                var usernameLink = null;
                
                for (var i = 0; i < usernameLinks.length; i++) {
                    if (usernameLinks[i].textContent.trim().length > 0) {
                        usernameLink = usernameLinks[i];
                        break;
                    }
                }
                
                var discuzUid = typeof discuz_uid !== 'undefined' ? discuz_uid : 0;
                
                return {
                    loggedIn: !!usernameLink && !loginLink && discuzUid > 0,
                    username: usernameLink ? usernameLink.textContent.trim() : null,
                    discuzUid: discuzUid,
                    hasLoginLink: !!loginLink
                };
            } catch(e) {
                return {loggedIn: false, error: e.message};
            }
        })();
        """
    }
    
    func getLogoutJavaScript() -> String {
        return """
        (function() {
            try {
                var logoutLinks = document.querySelectorAll('a[href*="logging.php?action=logout"], a[href*="member.php?action=loggingout"]');
                if (logoutLinks.length > 0) {
                    window.location.href = logoutLinks[0].href;
                    return {status: 'redirecting'};
                }

                var xhr = new XMLHttpRequest();
                xhr.open('GET', 'logging.php?action=logout&formhash=' + (typeof formhash !== 'undefined' ? formhash : ''), false);
                xhr.send();

                return {status: 'done', redirect: xhr.responseURL};
            } catch(e) {
                return {status: 'error', message: e.message};
            }
        })();
        """
    }

    // MARK: - Native Login

    /// 用已保存的凭证重新登录（会话过期时调用）
    @discardableResult
    func loginWithNetwork() async throws -> Bool {
        guard let username = currentUsername,
              let password = password else {
            return false
        }

        let result = try await NetworkManager.shared.nativeLogin(
            username: username,
            password: password,
            questionId: questionId,
            answer: answer ?? ""
        )

        applySuccessfulLogin(result: result, password: password, answer: answer ?? "")
        return true
    }

    /// 登录成功后的统一收尾：写入凭证、账号与 Cookie。
    ///
    /// 登录流程的各条路径（原生登录、WebView 兜底）都收敛到这里，
    /// 避免各自实现一套、顺序不一致再把 Cookie 冲掉。
    func applySuccessfulLogin(result: NetworkManager.NativeLoginResult, password: String, answer: String) {
        self.uid = result.uid
        self.isLoggedIn = true

        saveCredentials(
            username: result.username,
            password: password,
            questionId: questionId,
            answer: answer,
            uid: result.uid
        )
    }
}

extension String {
    var escapedForJavaScript: String {
        return self.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "'", with: "\\'")
                   .replacingOccurrences(of: "\n", with: "\\n")
                   .replacingOccurrences(of: "\r", with: "\\r")
    }

    var jsEscaped: String {
        return self.escapedForJavaScript
    }
}
