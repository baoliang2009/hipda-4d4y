import Foundation

/// 账号模型
struct Account: Codable, Equatable {
    let id: String // 唯一标识符 (使用 UUID)
    let username: String
    var uid: Int // 登录成功后才能从页面解析出来，需要可回填
    var questionId: Int
    var lastLoginDate: Date
    var isActive: Bool // 当前激活的账号

    init(username: String, uid: Int, questionId: Int) {
        self.id = UUID().uuidString
        self.username = username
        self.uid = uid
        self.questionId = questionId
        self.lastLoginDate = Date()
        self.isActive = false
    }

    /// Keychain key for password
    var passwordKey: String {
        return "account_password_\(id)"
    }

    /// Keychain key for security answer
    var answerKey: String {
        return "account_answer_\(id)"
    }

    /// Cookie storage key
    var cookiesKey: String {
        return "account_cookies_\(id)"
    }

    static func == (lhs: Account, rhs: Account) -> Bool {
        return lhs.id == rhs.id
    }
}
