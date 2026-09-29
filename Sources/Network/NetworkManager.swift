import Foundation
import SwiftSoup

enum NetworkError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(statusCode: Int?)
    case parsingFailed(String)
    case loginFailed(String)
    case timeout
    case noConnection
    case serverError(statusCode: Int)
    case notFound
    case unauthorized
    case postFailed(String)

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .requestFailed(let error):
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                return "连接超时，请检查网络后重试"
            } else if nsError.code == NSURLErrorNotConnectedToInternet {
                return "无网络连接，请检查网络设置"
            } else if nsError.code == NSURLErrorCannotFindHost {
                return "无法连接到服务器"
            }
            return "网络请求失败: \(error.localizedDescription)"
        case .invalidResponse(let statusCode):
            if let code = statusCode {
                return "服务器响应异常 (HTTP \(code))"
            }
            return "服务器响应无效"
        case .parsingFailed(let detail):
            return "数据解析失败: \(detail)"
        case .loginFailed(let detail):
            return "登录失败: \(detail)"
        case .timeout:
            return "请求超时，请稍后重试"
        case .noConnection:
            return "无网络连接"
        case .serverError(let statusCode):
            return "服务器错误 (HTTP \(statusCode))"
        case .notFound:
            return "请求的内容不存在"
        case .unauthorized:
            return "未授权，请重新登录"
        case .postFailed(let detail):
            return detail
        }
    }

    /// Check if error is recoverable with retry
    var isRetryable: Bool {
        switch self {
        case .timeout, .noConnection, .requestFailed, .serverError:
            return true
        default:
            return false
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()

    let session: URLSession
    private let baseURL = URL(string: "https://www.4d4y.com/forum/")!

    // Chinese encodings for Discuz forums
    private let gb18030: String.Encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
    private let gb2312: String.Encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630)))

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        // Use shared cookie storage to sync cookies with WKWebView
        config.httpCookieStorage = HTTPCookieStorage.shared
        session = URLSession(configuration: config)
    }

    // MARK: - Request Execution

    /// 所有原生请求的统一出口。
    ///
    /// 做两件事：
    /// 1. 补齐与 WebView 一致的浏览器特征头（UA 必须一致，否则 cf_clearance 失效）
    /// 2. 遇到 Cloudflare 质询（403 + `cf-mitigated: challenge`）时，用隐藏 WebView
    ///    刷新一次 clearance 再重试。clearance 有效期只有几十分钟到几小时，
    ///    过期后所有原生请求都会 403，必须能自愈。
    ///
    /// - Parameter allowChallengeRetry: 内部重试时置为 false，避免无限递归
    func send(_ request: URLRequest, allowChallengeRetry: Bool = true) async throws -> (Data, URLResponse) {
        var outgoing = request
        WebClientConfig.applyBrowserHeaders(to: &outgoing)

        let (data, response) = try await session.data(for: outgoing)

        guard allowChallengeRetry,
              let http = response as? HTTPURLResponse,
              Self.isCloudflareChallenge(http) else {
            return (data, response)
        }

        print("[Network] Cloudflare challenge on \(request.url?.path ?? "?"), refreshing clearance...")

        let refreshed = await CloudflareManager.shared.refreshClearance()
        guard refreshed else {
            print("[Network] Clearance refresh failed, returning original 403")
            return (data, response)
        }

        print("[Network] Clearance refreshed, retrying request")
        return try await send(request, allowChallengeRetry: false)
    }

    /// 判断响应是不是 Cloudflare 的质询页，而不是站点自己返回的 403
    private static func isCloudflareChallenge(_ response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 403 else { return false }

        // Cloudflare 拦截时会带上这个头，是最准确的判据
        if let mitigated = response.value(forHTTPHeaderField: "cf-mitigated"),
           mitigated.caseInsensitiveCompare("challenge") == .orderedSame {
            return true
        }

        // 兜底：403 且由 Cloudflare 边缘返回
        if let server = response.value(forHTTPHeaderField: "Server"),
           server.caseInsensitiveCompare("cloudflare") == .orderedSame {
            return true
        }

        return false
    }

    // Helper to decode HTML data with proper encoding
    private func decodeHTMLData(_ data: Data) throws -> String {
        let encodings: [String.Encoding] = [.utf8, gb18030, gb2312, .windowsCP1252]

        for encoding in encodings {
            if let html = String(data: data, encoding: encoding) {
                return html
            }
        }

        throw NetworkError.parsingFailed("Failed to decode HTML with any encoding")
    }

    // MARK: - Login

    func fetchLoginPage() async throws -> LoginFormData {
        let url = baseURL.appendingPathComponent("logging.php?action=login")

        var request = URLRequest(url: url)
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")

        let (data, response) = try await send(request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }

        let html = try decodeHTMLData(data)
        print("[LoginPage] HTML length: \(html.count)")
        print("[LoginPage] HTML sample (first 300 chars): \(String(html.prefix(300)))")

        return try ForumHTMLParser.parseLoginPage(html)
    }

    // MARK: - Native Login

    struct NativeLoginResult {
        let uid: Int
        let username: String
    }

    /// 原生登录（URLSession）。
    ///
    /// **为什么不再走 WKWebView**：实测 Cloudflare 只对本 App 的 WKWebView 下发
    /// Turnstile 托管质询，且无论等多久都过不去（挑战页每 ~45 秒自我刷新一次，
    /// turnstile iframe 反复 -999）；而同一台设备上 URLSession 的请求可以直接
    /// 拿到 200 + 真实 Discuz 页面——Apple 网络栈的 TLS 指纹被 Cloudflare 放行了。
    /// 所以登录这条路必须由 URLSession 走，WebView 反而是被堵死的那条。
    func nativeLogin(username: String, password: String, questionId: Int, answer: String) async throws -> NativeLoginResult {
        // 1) 取登录页，拿 formhash，并判断该站是否在前端做 MD5
        let (loginPageHTML, formhash) = try await fetchLoginForm()

        // Discuz 有的站点用 md5.js 在前端把密码 hash 后再提交，有的直接交明文由后端 hash。
        // 提交错形式会一律报"密码错误"，所以先按页面实际引用的脚本判断。
        let usesClientSideMD5 = loginPageHTML.contains("hex_md5") || loginPageHTML.contains("md5.js")
        print("[NativeLogin] formhash=\(formhash), clientSideMD5=\(usesClientSideMD5)")

        // 2) 提交。上面的判断未必准，失败后用另一种形式再试一次
        var lastError: String?
        var triedForms = Set<Bool>()

        for useMD5 in [usesClientSideMD5, !usesClientSideMD5] where !triedForms.contains(useMD5) {
            triedForms.insert(useMD5)

            let responseText = try await submitLoginForm(
                formhash: formhash,
                username: username,
                password: useMD5 ? password.md5 : password,
                questionId: questionId,
                answer: answer
            )

            // 3) 以论坛页面上的 discuz_uid 为准验证。
            //    不要去解析登录接口返回的那段 XML——成功与失败都可能是 200，
            //    而且内容是 GBK，靠文案判断容易误判。
            if let result = try await verifyLoggedIn(fallbackUsername: username) {
                print("[NativeLogin] Success: uid=\(result.uid), username=\(result.username), md5=\(useMD5)")
                return result
            }

            lastError = Self.loginErrorMessage(from: responseText)
            print("[NativeLogin] Attempt failed (md5=\(useMD5)): \(lastError ?? "unknown")")
        }

        throw NetworkError.loginFailed(lastError ?? "用户名或密码错误")
    }

    /// 取登录页 HTML 与 formhash
    private func fetchLoginForm() async throws -> (html: String, formhash: String) {
        var request = URLRequest(url: URL(string: "https://www.4d4y.com/forum/logging.php?action=login")!)
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")

        let (data, response) = try await send(request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw NetworkError.loginFailed("无法打开登录页 (HTTP \(code.map(String.init) ?? "?"))")
        }

        let html = try decodeHTMLData(data)
        guard let formhash = ForumHTMLParser.extractFormhash(html), !formhash.isEmpty else {
            throw NetworkError.loginFailed("无法获取登录表单")
        }
        return (html, formhash)
    }

    /// 提交登录表单，返回响应正文（用于失败时提取原因）
    private func submitLoginForm(formhash: String,
                                 username: String,
                                 password: String,
                                 questionId: Int,
                                 answer: String) async throws -> String {
        let url = URL(string: "https://www.4d4y.com/forum/logging.php?action=login&loginsubmit=yes&inajax=1")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.4d4y.com/forum/logging.php?action=login", forHTTPHeaderField: "Referer")
        request.setValue("https://www.4d4y.com", forHTTPHeaderField: "Origin")

        // 站点是 GBK，表单必须按 GBK 逐字节做百分号编码。
        // 用 UTF-8 编码会让中文用户名和安全提问答案在服务端变成乱码，登录必然失败。
        let fields: [(String, String)] = [
            ("formhash", formhash),
            ("referer", "https://www.4d4y.com/forum/"),
            ("loginfield", "username"),
            ("username", username),
            ("password", password),
            ("questionid", String(questionId)),
            ("answer", answer),
            ("cookietime", "2592000")
        ]
        let body = fields
            .map { "\($0.0)=\(Self.gbkPercentEncoded($0.1))" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .ascii)

        let (data, _) = try await send(request)
        return (try? decodeHTMLData(data)) ?? ""
    }

    /// 从论坛首页确认是否已登录，并取回 uid
    private func verifyLoggedIn(fallbackUsername: String) async throws -> NativeLoginResult? {
        var request = URLRequest(url: URL(string: "https://www.4d4y.com/forum/index.php")!)
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")

        let (data, _) = try await send(request)
        let html = (try? decodeHTMLData(data)) ?? ""

        let uid = Self.extractDiscuzUid(from: html)
        guard uid > 0 else { return nil }

        let name = Self.extractLoggedInUsername(from: html) ?? fallbackUsername
        return NativeLoginResult(uid: uid, username: name)
    }

    /// 按 GBK 逐字节做百分号编码
    static func gbkPercentEncoded(_ value: String) -> String {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
        // GBK 编不出来的字符退回 UTF-8，总比整个串丢掉强
        let data = value.data(using: gbk) ?? Data(value.utf8)

        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~".utf8)
        var out = ""
        for byte in data {
            if unreserved.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// 解析页面里的 `discuz_uid`。Discuz 每个页面的 <head> 都会输出这个全局变量，
    /// 是判断登录态最可靠的依据。
    static func extractDiscuzUid(from html: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "discuz_uid\\s*=\\s*'?(\\d+)'?") else { return 0 }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return 0 }
        return Int(html[r]) ?? 0
    }

    /// 从顶部用户菜单里取用户名
    private static func extractLoggedInUsername(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "space\\.php\\?uid=\\d+[^>]*>([^<]+)</a>") else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        let name = html[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 从登录接口的返回里提取可读的失败原因
    private static func loginErrorMessage(from response: String) -> String? {
        let patterns: [(String, String)] = [
            ("密码错误次数过多", "密码错误次数过多，请稍后再试"),
            ("安全提问", "安全提问答案错误"),
            ("验证码", "需要输入验证码，请稍后重试"),
            ("您还可以尝试", "用户名或密码错误")
        ]
        for (needle, message) in patterns where response.contains(needle) {
            return message
        }
        return nil
    }

    // MARK: - Forum List

    func fetchForumList(useCache: Bool = true) async throws -> [Forum] {
        let cacheKey = CacheManager.CacheKeys.forumList()

        // Try cache first
        if useCache, let cachedForums: [Forum] = CacheManager.shared.load([Forum].self, forKey: cacheKey) {
            print("[ForumList] Using cache, age: \(CacheManager.shared.getCacheAge(forKey: cacheKey) ?? "unknown")")
            // Refresh in background
            Task {
                if let freshForums = try? await self.fetchForumListWithoutCache() {
                    CacheManager.shared.save(freshForums, forKey: cacheKey)
                }
            }
            return cachedForums
        }

        // Fetch from network
        let forums = try await fetchForumListWithoutCache()
        CacheManager.shared.save(forums, forKey: cacheKey)
        return forums
    }

    func fetchForumListWithoutCache() async throws -> [Forum] {
        let urlString = "https://www.4d4y.com/forum/index.php"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // Debug: Print cookies before request
        if let cookies = HTTPCookieStorage.shared.cookies {
            let cookieStr = cookies.map { "\($0.name)=\($0.value.prefix(10))..." }.joined(separator: "; ")
            print("[Network] ForumList cookies BEFORE request: \(cookieStr)")
        } else {
            print("[Network] ForumList: No cookies in HTTPCookieStorage.shared")
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        let (data, response) = try await send(request)

        // Debug: Print raw response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: nil)
        }

        print("[Network] ForumList HTTP status: \(httpResponse.statusCode)")
        print("[Network] ForumList response headers: \(httpResponse.allHeaderFields)")

        // Handle different HTTP status codes
        switch httpResponse.statusCode {
        case 200...299:
            break // Success
        case 401:
            throw NetworkError.unauthorized
        case 404:
            throw NetworkError.notFound
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        // Try multiple encodings
        let encodings: [String.Encoding] = [.utf8, gb18030, gb2312, .windowsCP1252]
        var decoded成功 = false
        for encoding in encodings {
            if let html = String(data: data, encoding: encoding) {
                print("[Network] ForumList response (\(encoding), first 2000 chars): \(String(html.prefix(2000)))")
                decoded成功 = true
                break
            }
        }
        if !decoded成功 {
            // Print raw bytes as hex for debugging
            let bytes = [UInt8](data.prefix(100))
            let hexStr = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[Network] ForumList response: (could not decode, first 100 bytes hex): \(hexStr)")
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }

        return try ForumHTMLParser.parseForumList(data)
    }

    // MARK: - Thread List

    func fetchThreadList(fid: Int, page: Int = 1, filter: String? = nil, orderby: String? = nil) async throws -> [ForumThread] {
        var urlString = "https://www.4d4y.com/forum/forumdisplay.php?fid=\(fid)&page=\(page)"

        if let filter = filter, !filter.isEmpty {
            urlString += "&filter=\(filter)"
        }
        if let orderby = orderby, !orderby.isEmpty {
            urlString += "&orderby=\(orderby)"
        }

        print("[Network] fetchThreadList URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // Debug: Print cookies before request
        if let cookies = HTTPCookieStorage.shared.cookies {
            let cookieStr = cookies.map { "\($0.name)=\($0.value.prefix(10))..." }.joined(separator: "; ")
            print("[Network] Cookies BEFORE request: \(cookieStr)")
        } else {
            print("[Network] No cookies in HTTPCookieStorage.shared")
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse(statusCode: nil)
            }

            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                break // Success
            case 401:
                throw NetworkError.unauthorized
            case 404:
                throw NetworkError.notFound
            case 500...599:
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            default:
                throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            return try ForumHTMLParser.parseThreadList(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    // MARK: - Thread Detail

    func fetchThreadDetail(tid: Int, page: Int = 1, useCache: Bool = true) async throws -> ThreadDetail {
        let cacheKey = CacheManager.CacheKeys.threadDetail(tid: tid, page: page)

        // Try cache first for page 1 (main content)
        if useCache, page == 1, let cachedDetail: ThreadDetail = CacheManager.shared.load(ThreadDetail.self, forKey: cacheKey) {
            print("[ThreadDetail] Using cache for tid=\(tid), age: \(CacheManager.shared.getCacheAge(forKey: cacheKey) ?? "unknown")")
            // Refresh in background
            Task {
                if let freshDetail = try? await self.fetchThreadDetailWithoutCache(tid: tid, page: page) {
                    CacheManager.shared.save(freshDetail, forKey: cacheKey)
                }
            }
            return cachedDetail
        }

        let detail = try await fetchThreadDetailWithoutCache(tid: tid, page: page)
        CacheManager.shared.save(detail, forKey: cacheKey)
        return detail
    }

    private func fetchThreadDetailWithoutCache(tid: Int, page: Int = 1) async throws -> ThreadDetail {
        let pageString = page > 1 ? "&page=\(page)" : ""
        let urlString = "https://www.4d4y.com/forum/viewthread.php?tid=\(tid)&highlight=\(pageString)"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse(statusCode: nil)
            }

            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                break // Success
            case 401:
                throw NetworkError.unauthorized
            case 404:
                throw NetworkError.notFound
            case 500...599:
                throw NetworkError.serverError(statusCode: httpResponse.statusCode)
            default:
                throw NetworkError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            return try ForumHTMLParser.parseThreadDetail(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    // MARK: - Reply

    // MARK: - Posting (native)
    //
    // 发帖/回复/附件全部走原生 URLSession。之前是用 WKWebView 打开 post.php 取
    // formhash 再 form.submit()，但 WKWebView 被 Cloudflare Turnstile 拦死（见
    // CLAUDE.md），formhash 根本取不到，功能名存实亡。原生请求能过 Cloudflare，
    // 表单结构已按真实页面核对：
    //   - 回复:   post.php?action=reply&fid=&tid=&extra=&replysubmit=yes
    //   - 发帖:   post.php?action=newthread&fid=&extra=&topicsubmit=yes
    //   - 传图:   misc.php?action=swfupload&operation=upload&simple=1&type=image
    //             (multipart: uid / hash / Filedata)，返回纯 aid
    // 提交表单一律按 GBK 逐字节百分号编码，否则中文标题/正文乱码。

    /// 发帖/回复页解析出的表单信息
    struct PostFormInfo {
        let fid: Int
        let tid: Int
        let formhash: String
        let posttime: String
        let uploadHash: String?   // 传图用的 hash，未登录/无附件权限时可能为空
    }

    /// 取回复页表单（formhash / posttime / 上传 hash / fid）
    func fetchReplyForm(tid: Int) async throws -> PostFormInfo {
        var request = URLRequest(url: URL(string: "https://www.4d4y.com/forum/post.php?action=reply&tid=\(tid)")!)
        request.setValue("https://www.4d4y.com/forum/viewthread.php?tid=\(tid)", forHTTPHeaderField: "Referer")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        let html = try decodeHTMLData(data)
        return try parsePostForm(html: html, fallbackTid: tid, fallbackFid: 0)
    }

    /// 取发帖页表单
    func fetchNewThreadForm(fid: Int) async throws -> PostFormInfo {
        var request = URLRequest(url: URL(string: "https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)")!)
        request.setValue("https://www.4d4y.com/forum/forumdisplay.php?fid=\(fid)", forHTTPHeaderField: "Referer")
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        let html = try decodeHTMLData(data)
        return try parsePostForm(html: html, fallbackTid: 0, fallbackFid: fid)
    }

    private func parsePostForm(html: String, fallbackTid: Int, fallbackFid: Int) throws -> PostFormInfo {
        // formhash 可能是隐藏 input，也可能只出现在链接的 ?formhash= 上
        let formhash = Self.firstMatch(#"name="formhash"\s+value="([^"]+)""#, in: html)
            ?? Self.firstMatch(#"formhash=([0-9a-fA-F]{6,})"#, in: html)
        guard let fh = formhash, !fh.isEmpty else {
            if html.contains("logging.php?action=login") || html.contains("您还没有登录") || html.contains("请先登录") {
                throw NetworkError.postFailed("请先登录后再操作")
            }
            throw NetworkError.postFailed("无法获取发帖表单，请稍后重试")
        }
        let posttime = Self.firstMatch(#"name="posttime"\s+value="(\d+)""#, in: html)
            ?? String(Int(Date().timeIntervalSince1970))
        let uploadHash = Self.firstMatch(#"name="hash"\s+value="([0-9a-fA-F]+)""#, in: html)
        let fid = Self.firstMatch(#"post\.php\?action=[a-z]+&(?:amp;)?fid=(\d+)"#, in: html).flatMap { Int($0) }
            ?? Self.firstMatch(#"[?&]fid=(\d+)"#, in: html).flatMap { Int($0) }
            ?? fallbackFid
        let tid = Self.firstMatch(#"[?&]tid=(\d+)"#, in: html).flatMap { Int($0) } ?? fallbackTid
        return PostFormInfo(fid: fid, tid: tid, formhash: fh, posttime: posttime, uploadHash: uploadHash)
    }

    /// 原生上传单张附件，返回附件 aid。上传成功后 Discuz 会把该附件挂在
    /// 当前用户本次会话（uid + hash）的待处理列表里，发帖/回复提交时自动关联。
    func uploadAttachment(imageData: Data, uid: Int, uploadHash: String, referer: String) async throws -> String {
        let url = URL(string: "https://www.4d4y.com/forum/misc.php?action=swfupload&operation=upload&simple=1&type=image")!
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 60

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("uid", String(uid))
        addField("hash", uploadHash)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"Filedata\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.postFailed("图片上传失败 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // simple=1 一般直接返回 aid；兜底取响应里的第一串数字
        if text.range(of: #"^\d+$"#, options: .regularExpression) != nil { return text }
        if let aid = Self.firstMatch(#"(\d+)"#, in: text), !aid.isEmpty { return aid }
        throw NetworkError.postFailed("图片上传失败：\(text.prefix(60))")
    }

    /// 原生回复。attachAids 为已上传附件 id，会以 [attachimg] 形式插入正文末尾以内联显示。
    func replyThread(tid: Int, fid: Int, message: String, formhash: String, posttime: String, attachAids: [String] = []) async throws -> Bool {
        var comps = URLComponents(string: "https://www.4d4y.com/forum/post.php")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "reply"),
            URLQueryItem(name: "tid", value: String(tid)),
            URLQueryItem(name: "extra", value: ""),
            URLQueryItem(name: "replysubmit", value: "yes")
        ]
        if fid > 0 { comps.queryItems?.insert(URLQueryItem(name: "fid", value: String(fid)), at: 1) }

        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.4d4y.com/forum/post.php?action=reply&tid=\(tid)", forHTTPHeaderField: "Referer")
        request.setValue("https://www.4d4y.com", forHTTPHeaderField: "Origin")

        let fields: [(String, String)] = [
            ("formhash", formhash),
            ("posttime", posttime),
            ("wysiwyg", "0"),
            ("subject", ""),
            ("message", Self.appendAttachTags(message, aids: attachAids)),
            ("usesig", "1")
        ]
        request.httpBody = fields.map { "\($0.0)=\(Self.gbkPercentEncoded($0.1))" }.joined(separator: "&").data(using: .ascii)
        return try await submitPostAndCheck(request)
    }

    // MARK: - Create Thread

    /// 原生发帖。
    func createThread(fid: Int, title: String, message: String, typeid: Int, tags: String, formhash: String, posttime: String, attachAids: [String] = []) async throws -> Bool {
        var comps = URLComponents(string: "https://www.4d4y.com/forum/post.php")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "newthread"),
            URLQueryItem(name: "fid", value: String(fid)),
            URLQueryItem(name: "extra", value: ""),
            URLQueryItem(name: "topicsubmit", value: "yes")
        ]

        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.4d4y.com/forum/post.php?action=newthread&fid=\(fid)", forHTTPHeaderField: "Referer")
        request.setValue("https://www.4d4y.com", forHTTPHeaderField: "Origin")

        var fields: [(String, String)] = [
            ("formhash", formhash),
            ("posttime", posttime),
            ("wysiwyg", "0"),
            ("subject", title),
            ("message", Self.appendAttachTags(message, aids: attachAids)),
            ("usesig", "1")
        ]
        if typeid > 0 { fields.insert(("typeid", String(typeid)), at: 3) }
        if !tags.isEmpty { fields.append(("tags", tags)) }
        request.httpBody = fields.map { "\($0.0)=\(Self.gbkPercentEncoded($0.1))" }.joined(separator: "&").data(using: .ascii)
        return try await submitPostAndCheck(request)
    }

    private static func appendAttachTags(_ message: String, aids: [String]) -> String {
        guard !aids.isEmpty else { return message }
        return message + "\n" + aids.map { "[attachimg]\($0)[/attachimg]" }.joined(separator: "\n")
    }

    /// 提交发帖/回复并判定结果。成功时 Discuz 会跳转到 viewthread（ASCII 可靠可判）；
    /// 否则尽量从返回页里认出中文错误提示，实在认不出给个通用失败。
    private func submitPostAndCheck(_ request: URLRequest) async throws -> Bool {
        let (data, response) = try await send(request)
        let finalURL = response.url?.absoluteString ?? ""
        let html = (try? decodeHTMLData(data)) ?? ""

        if finalURL.contains("viewthread.php") || html.contains("viewthread.php?tid=") || html.contains("resultmessage") && html.contains("success") {
            return true
        }

        let errorKeywords: [(String, String)] = [
            ("两次发表", "发帖过于频繁，请稍后再试"),
            ("间隔", "发帖过于频繁，请稍后再试"),
            ("验证码", "该操作需要验证码，暂不支持"),
            ("无权", "没有权限在该板块发帖/回复"),
            ("权限", "没有权限在该板块发帖/回复"),
            ("标题不能为空", "标题不能为空"),
            ("内容不能为空", "内容不能为空"),
            ("字数", "内容长度不符合要求"),
            ("登录", "登录状态已失效，请重新登录"),
            ("抱歉", "发帖失败，请稍后重试")
        ]
        for (kw, msg) in errorKeywords where html.contains(kw) {
            throw NetworkError.postFailed(msg)
        }
        throw NetworkError.postFailed("发帖结果未确认，请回到帖子检查是否已发出")
    }

    /// 取正则第一个捕获组
    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - Logout

    func logout(formhash: String) async throws {
        let url = baseURL.appendingPathComponent("logging.php?action=logout&formhash=\(formhash)")
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 302 else {
            throw NetworkError.invalidResponse(statusCode: nil)
        }
    }

    // MARK: - Private Messages

    func fetchPrivateMessages(page: Int = 1) async throws -> [PrivateMessage] {
        let urlString = "https://www.4d4y.com/forum/pm.php?page=\(page)"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidResponse(statusCode: nil)
            }

            return try ForumHTMLParser.parsePrivateMessages(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    // MARK: - PM Detail

    func fetchPMDetail(uid: Int, page: Int = 1) async throws -> PMDetail {
        let urlString = "https://www.4d4y.com/forum/pm.php?uid=\(uid)&filter=privatepm&daterange=5&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidResponse(statusCode: nil)
            }

            return try ForumHTMLParser.parsePMDetail(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    /// 原生发送私信。
    /// 表单来自 pm.php 的回复框：action=pm.php?action=send&uid=X&pmsubmit=yes&infloat=yes
    /// body 需含 formhash / handlekey=pmreply / lastdaterange / message，且按 GBK 编码。
    func sendPM(uid: Int, message: String, formhash: String, lastDateRange: String = "") async throws -> Bool {
        let url = URL(string: "https://www.4d4y.com/forum/pm.php?action=send&uid=\(uid)&pmsubmit=yes&infloat=yes&inajax=1")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.4d4y.com/forum/pm.php?uid=\(uid)&filter=privatepm&daterange=5", forHTTPHeaderField: "Referer")
        request.setValue("https://www.4d4y.com", forHTTPHeaderField: "Origin")

        let fields: [(String, String)] = [
            ("formhash", formhash),
            ("handlekey", "pmreply"),
            ("lastdaterange", lastDateRange),
            ("message", message)
        ]
        let body = fields.map { "\($0.0)=\(Self.gbkPercentEncoded($0.1))" }.joined(separator: "&")
        request.httpBody = body.data(using: .ascii)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }

        // Discuz inajax 返回里出现明确错误提示才算失败；成功一般是 succeedhandle / 空 root
        let html = (try? decodeHTMLData(data)) ?? ""
        if html.contains("请不要") || html.contains("错误") || html.contains("无权") {
            throw NetworkError.loginFailed("发送失败")
        }
        return true
    }

    // MARK: - User Profile

    func fetchUserProfile(uid: Int) async throws -> ForumUser {
        let urlString = "https://www.4d4y.com/forum/space.php?uid=\(uid)"

        print("[UserProfile] Request URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            // Debug: Print response info
            if let httpResponse = response as? HTTPURLResponse {
                print("[UserProfile] Response Status: \(httpResponse.statusCode)")
                print("[UserProfile] Response URL: \(httpResponse.url?.absoluteString ?? "nil")")
                print("[UserProfile] All Header Fields: \(httpResponse.allHeaderFields)")
            }

            // Debug: Print raw data info
            print("[UserProfile] Data length: \(data.count) bytes")
            if let firstBytes = String(data: data.prefix(100), encoding: .utf8) {
                print("[UserProfile] First 100 bytes (UTF8): \(firstBytes)")
            } else {
                print("[UserProfile] First 100 bytes (hex): \(data.prefix(100).map { String(format: "%02x", $0) }.joined(separator: " "))")
            }

            // Debug: Print response body (first 2000 chars) - try multiple encodings
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
            let gb2312 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630)))
            var decodedHtml: String?
            for encoding in [gb18030, gb2312, .utf8] {
                if let html = String(data: data, encoding: encoding) {
                    decodedHtml = html
                    print("[UserProfile] Decoded with: \(encoding)")
                    break
                }
            }
            if let html = decodedHtml {
                print("[UserProfile] Response Body (first 2000 chars):")
                print(String(html.prefix(2000)))
            } else {
                print("[UserProfile] Response Body: (unable to decode)")
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidResponse(statusCode: nil)
            }

            return try ForumHTMLParser.parseUserProfile(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    // MARK: - Search

    func search(keyword: String, page: Int = 1) async throws -> SearchDetail {
        // 关键词必须按 GBK 百分号编码。
        // 站点是 GBK，用 addingPercentEncoding（UTF-8）编出来的中文服务端认不出，
        // 任何中文关键词都会返回"没有找到匹配结果"。实测：
        //   「深信服」UTF-8 编码 → 0 条； GBK 编码 → 41 条
        let encodedKeyword = Self.gbkPercentEncoded(keyword)
        let urlString = "https://www.4d4y.com/forum/search.php?srchtype=title&srchtxt=\(encodedKeyword)&searchsubmit=true&st=on&srchuname=&srchfilter=all&srchfrom=0&before=&orderby=lastpost&ascdesc=desc&page=\(page)"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://www.4d4y.com/forum/search.php", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await send(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
            }

            let html = try decodeHTMLData(data)

            // 返回 200 不代表搜索成功：Discuz 会用同样的 200 页面回各种拦截提示。
            // 这些情况必须抛出可读原因，否则界面只会显示"未找到"，与真无结果无法区分。
            if html.contains("两次搜索") || html.contains("搜索间隔") || html.contains("间隔不能小于") {
                throw NetworkError.loginFailed("搜索太频繁，请稍后再试")
            }
            if html.contains("您所在的用户组无法使用搜索") || html.contains("无权") {
                throw NetworkError.loginFailed("当前账号无搜索权限")
            }
            if html.contains("请先登录") || html.contains("您需要先登录") {
                throw NetworkError.unauthorized
            }

            return try ForumHTMLParser.parseSearchResults(data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }
}

// MARK: - String MD5 Extension

extension String {
    var md5: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: 16)

        _ = data.withUnsafeBytes { buffer in
            CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }

        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto
