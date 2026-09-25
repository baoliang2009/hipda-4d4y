import Foundation
import SwiftSoup

class ForumHTMLParser {

    // Chinese encodings
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631)))
    private static let gb2312 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630)))

    // MARK: - Forum List Parsing

    static func parseForumList(_ data: Data) throws -> [Forum] {
        // Try multiple encodings
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode HTML")
        }

        let doc = try SwiftSoup.parse(decodedHTML)
        var forums: [Forum] = []

        // Parse forums from <tbody id="forum{fid}"> elements
        let forumBodies = try doc.select("tbody[id^='forum']")
        print("[ForumParser] Found \(forumBodies.count) forum tbody elements")

        for tbody in forumBodies {
            guard let forumData = try? parseForumTbody(tbody) else { continue }
            forums.append(forumData)
        }

        return forums
    }

    private static func parseForumTbody(_ tbody: Element) throws -> Forum? {
        // Extract fid from tbody id (e.g., "forum25" -> 25)
        let tbodyId = try tbody.attr("id")
        guard tbodyId.hasPrefix("forum"), let fid = Int(tbodyId.dropFirst(5)) else {
            return nil
        }

        // Find forum name from h2 > a
        guard let nameLink = try? tbody.select("h2 a[href*='forumdisplay.php?fid=']").first(),
              let name = try? nameLink.text() else {
            return nil
        }

        // Find description from div.left > p
        var description = ""
        if let divLeft = try? tbody.select("div.left").first(),
           let p = try? divLeft.select("p").first() {
            description = try p.text()
        }

        // Find thread/post counts from td.forumnums
        // HTML: <em>8598</em> / 109229 -> <em>是回复数</em>, 后面的109229是发帖数
        var threadCount = 0
        var postCount = 0
        if let numsTd = try? tbody.select("td.forumnums").first() {
            // Get the <em> element text (reply count)
            if let em = try? numsTd.select("em").first() {
                let emText = try em.text().replacingOccurrences(of: ",", with: "")
                postCount = Int(emText) ?? 0
            }
            // Get the text after / (thread count)
            let numsText = try numsTd.text() // e.g., "8598 / 109229"
            let parts = numsText.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                // parts[1] is thread count (after /)
                let threadText = parts[1].replacingOccurrences(of: ",", with: "")
                threadCount = Int(threadText) ?? 0
            }
        }

        return Forum(fid: fid, name: name, description: description, threadCount: threadCount, postCount: postCount)
    }

    // MARK: - Thread List Parsing

    static func parseThreadList(_ data: Data) throws -> [ForumThread] {
        // Try multiple encodings for Chinese websites (Discuz uses GBK/GB2312)
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))), // GB18030
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))), // GB2312
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))), // GBK
            .utf8,
            .windowsCP1252
        ]

        var decodedHTML: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                decodedHTML = decoded
                break
            }
        }

        guard let html = decodedHTML else {
            throw NetworkError.parsingFailed("Failed to decode HTML with any encoding")
        }

        let doc = try SwiftSoup.parse(html)
        var threads: [ForumThread] = []

        // Try common thread list selectors for Discuz
        let threadRows = try doc.select("tbody[id^='stickthread_'], tbody[id^='normalthread_']")
        print("[ForumParser] Found \(threadRows.count) thread rows")

        for row in threadRows {
            guard let thread = try? parseThreadRow(row) else { continue }
            threads.append(thread)
        }

        // Alternative: parse from table rows
        if threads.isEmpty {
            let allRows = try doc.select("tr")
            for row in allRows {
                if let thread = try? parseThreadRow(row) {
                    threads.append(thread)
                }
            }
        }

        // Last resort: try to find links to viewthread.php
        if threads.isEmpty {
            print("[ForumParser] No threads found via tbody, trying last resort method...")
            let threadLinks = try doc.select("a[href*='viewthread.php?tid=']")
            print("[ForumParser] Found \(threadLinks.count) viewthread links")
            for link in threadLinks {
                if let href = try? link.attr("href"),
                   let tid = extractTidFromURL(href) {
                    let title = (try? link.text()) ?? "无标题"
                    let thread = ForumThread(
                        tid: tid,
                        title: title,
                        author: "未知",
                        authorUid: 0,
                        replyCount: 0,
                        viewCount: 0,
                        lastPostDate: "",
                        lastPostAuthor: ""
                    )
                    threads.append(thread)
                }
            }
        }

        return threads
    }

    private static func parseThreadRow(_ row: Element) throws -> ForumThread? {
        // Try to get tid from id first
        let id = try row.attr("id")
        var tid: Int?

        if id.hasPrefix("stickthread_") || id.hasPrefix("normalthread_") {
            let tidString = id.replacingOccurrences(of: "stickthread_", with: "").replacingOccurrences(of: "normalthread_", with: "")
            tid = Int(tidString)
        }

        // If no tid from id, try to extract from thread link
        if tid == nil {
            if let threadLink = try? row.select("a[href*='viewthread.php?tid=']").first(),
               let href = try? threadLink.attr("href") {
                tid = extractTidFromURL(href)
            }
        }

        guard let threadId = tid else { return nil }

        // Extract title - from th.subject
        var title = "无标题"
        if let thSubject = try? row.select("th.subject").first(),
           let titleLink = try? thSubject.select("a[href*='viewthread.php?tid=']").first() {
            title = try titleLink.text()
        }

        // Extract author - from td.author
        var author = "匿名"
        if let authorCell = try? row.select("td.author").first(),
           let authorLink = try? authorCell.select("a[href*='space.php?uid=']").first() {
            author = try authorLink.text()
        }

        // Extract author uid
        var authorUid = 0
        if let authorCell = try? row.select("td.author").first(),
           let authorLink = try? authorCell.select("a[href*='space.php?uid=']").first(),
           let href = try? authorLink.attr("href") {
            authorUid = extractUidFromURL(href)
        }

        // Extract reply/view count from <td class="nums"><strong>6</strong>/<em>226</em></td>
        var replyCount = 0
        var viewCount = 0
        if let numsCell = try? row.select("td.nums").first() {
            // Get reply count from <strong> tag
            if let strongEl = try? numsCell.select("strong").first() {
                let replyText = try strongEl.text().replacingOccurrences(of: ",", with: "")
                replyCount = Int(replyText) ?? 0
            }
            // Get view count from <em> tag
            if let emEl = try? numsCell.select("em").first() {
                let viewText = try emEl.text().replacingOccurrences(of: ",", with: "")
                viewCount = Int(viewText) ?? 0
            }
        }

        // Extract last post info
        var lastPostAuthor = ""
        var lastPostDate = ""
        if let lastPostEl = try? row.select(".lastpost, td.lastpost").first() {
            let text = try lastPostEl.text()
            lastPostAuthor = extractLastPostAuthor(from: text)
            lastPostDate = extractLastPostDate(from: text)
        }

        return ForumThread(
            tid: threadId,
            title: title,
            author: author,
            authorUid: authorUid,
            replyCount: replyCount,
            viewCount: viewCount,
            lastPostDate: lastPostDate,
            lastPostAuthor: lastPostAuthor
        )
    }

    // MARK: - Thread Detail Parsing

    static func parseThreadDetail(_ data: Data) throws -> ThreadDetail {
        // Try multiple encodings
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode HTML")
        }

        let doc = try SwiftSoup.parse(decodedHTML)

        // Extract title from h1 in threadtitle
        var title = "无标题"
        if let threadTitleDiv = try doc.select("#threadtitle h1").first() {
            title = try threadTitleDiv.text()
        } else if let pageTitle = try doc.select("title").first()?.text() {
            let parts = pageTitle.components(separatedBy: " - ")
            if parts.count >= 3 {
                title = parts[0].trimmingCharacters(in: .whitespaces)
            }
        }

        // Extract pagination info
        let paginationElement = try doc.select(".pg, .pagination").first()
        let paginationText = try paginationElement?.text() ?? ""
        let (currentPage, totalPages) = extractPageInfo(from: paginationText)

        // Parse posts
        var posts: [ForumPost] = []

        // Find all post divs - format is <div id="post_数字">
        let postDivs = try doc.select("div[id^='post_']")
        print("[parseThreadDetail] Found \(postDivs.count) post divs with selector div[id^='post_']")

        // If no posts found, try alternative selectors
        if postDivs.isEmpty() {
            print("[parseThreadDetail] Trying alternative selectors...")

            // Try table#pid* selector
            let altPostTables = try doc.select("table[id^='pid']")
            print("[parseThreadDetail]   table[id^='pid'] found: \(altPostTables.count)")

            // Try looking for any element with id containing "post"
            let anyPostId = try doc.select("[id*='post']")
            print("[parseThreadDetail]   [id*='post'] found: \(anyPostId.count)")

            // Print sample of body HTML
            if let body = try? doc.body() {
                let html = try? body.html()
                print("[parseThreadDetail]   Body HTML sample: \(String((html ?? "").prefix(500)))")
            }
        }

        // Debug: print first few post div IDs
        for (index, postDiv) in postDivs.array().enumerated() {
            if index < 3 {
                let id = try? postDiv.attr("id")
                print("[parseThreadDetail]   postDiv[\(index)] id: \(id ?? "nil")")
            }
        }

        for (index, postDiv) in postDivs.array().enumerated() {
            if let post = try? parsePostDiv(postDiv, floorNumber: index + 1) {
                posts.append(post)
            }
        }

        print("[parseThreadDetail] Parsed \(posts.count) posts")

        return ThreadDetail(
            title: title,
            posts: posts,
            totalPages: totalPages,
            currentPage: currentPage
        )
    }

    private static func parsePostDiv(_ postDiv: Element, floorNumber: Int) throws -> ForumPost? {
        // Extract pid from id (format: post_数字)
        let id = try postDiv.attr("id")
        guard id.hasPrefix("post_") else { return nil }

        let pidString = String(id.dropFirst(5)) // Remove "post_" prefix
        guard let pid = Int(pidString) else { return nil }

        // Extract author from td.postauthor
        var author = "匿名"
        var authorUid = 0
        var authorAvatar: String? = nil

        if let authorCell = try? postDiv.select("td.postauthor").first() {
            // Author name is in a link within the postauthor cell
            if let authorLink = try? authorCell.select("a[href*='space.php?uid=']").first() {
                author = try authorLink.text()
                if let href = try? authorLink.attr("href") {
                    authorUid = extractUidFromURL(href)
                }
            }

            // Extract avatar - look for img tag in postauthor cell
            if let avatarImg = try? authorCell.select("img[src*='avatar'], img.av, .avatar img").first() {
                authorAvatar = try avatarImg.attr("src")
            }
        }

        // Extract post date - look for "发表于" pattern in the post
        var postDate = ""
        if let postinfo = try? postDiv.select(".postinfo, .posterinfo").first() {
            let text = try postinfo.text()
            // Look for date pattern like "发表于 2009-1-2 01:17"
            if let range = text.range(of: "\\d{4}-\\d{1,2}-\\d{1,2}\\s+\\d{1,2}:\\d{2}", options: .regularExpression) {
                postDate = String(text[range])
            }
        }

        // Extract content from td.t_msgfont or element with id="postmessage_*"
        var content = ""
        var images: [String] = []

        // Try multiple selectors for content
        var contentCell: Element? = nil
        if let cell = try? postDiv.select("td.t_msgfont").first() {
            contentCell = cell
        } else if let cell = try? postDiv.select("*[id^='postmessage_']").first() {
            contentCell = cell
        }

        if contentCell == nil {
            print("[parsePostDiv] WARNING: No content cell found in post div, trying raw text extraction")
            // Last resort: get all text from the post div
            if let text = try? postDiv.text(), !text.isEmpty {
                content = text
                print("[parsePostDiv] Raw text: \(text.prefix(50))...")
            }
        }

        if let cell = contentCell {
            // Get text content
            content = try cell.text()
            print("[parsePostDiv] Found content: \(content.prefix(50))...")

            // Get full HTML to extract image URLs
            if let htmlContent = try? cell.html() {
                // Extract image URLs from zoom(this, 'url') pattern
                // Pattern: zoom(this, 'https://...')
                let zoomPattern = #"zoom\(this,\s*'([^']+)'"#
                if let regex = try? NSRegularExpression(pattern: zoomPattern, options: []) {
                    let range = NSRange(htmlContent.startIndex..., in: htmlContent)
                    let matches = regex.matches(in: htmlContent, options: [], range: range)
                    for match in matches {
                        if let urlRange = Range(match.range(at: 1), in: htmlContent) {
                            let url = String(htmlContent[urlRange])
                            if url.hasPrefix("http") && !images.contains(url) {
                                images.append(url)
                            }
                        }
                    }
                }

                // Also try href pattern for direct links (e.g., <a href="..."><img...></a>)
                let hrefPattern = #"<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>.*?<img[^>]+src=[\"']([^\"']+)[\"']"#
                if let regex = try? NSRegularExpression(pattern: hrefPattern, options: [.dotMatchesLineSeparators]) {
                    let range = NSRange(htmlContent.startIndex..., in: htmlContent)
                    let matches = regex.matches(in: htmlContent, options: [], range: range)
                    for match in matches {
                        if let hrefRange = Range(match.range(at: 1), in: htmlContent) {
                            let hrefURL = String(htmlContent[hrefRange])
                            // Check if href looks like an image URL (has image extension or attachment)
                            if hrefURL.hasPrefix("http") &&
                               (hrefURL.contains("attachment") || hrefURL.contains("image") || isLikelyImageURL(hrefURL)) &&
                               !images.contains(hrefURL) {
                                images.append(hrefURL)
                            }
                        }
                    }
                }

                // Fallback: extract from src if no zoom pattern found
                if images.isEmpty {
                    let srcPattern = #"src=[\"']([^\"']+)[\"']"#
                    if let regex = try? NSRegularExpression(pattern: srcPattern, options: []) {
                        let range = NSRange(htmlContent.startIndex..., in: htmlContent)
                        let matches = regex.matches(in: htmlContent, options: [], range: range)
                        for match in matches {
                            if let urlRange = Range(match.range(at: 1), in: htmlContent) {
                                let url = String(htmlContent[urlRange])
                                // Only exclude specific navigation/icon images
                                let excludedPatterns = ["back.gif", "forward.gif", "reply.gif", "new_pm.gif", "post_thumbia", "small", "icon"]
                                let isExcluded = excludedPatterns.contains { url.lowercased().contains($0) }
                                // Only use image URLs that are likely actual post content images
                                if url.hasPrefix("http") && !url.contains(".thumb") && !url.contains("_small") && !isExcluded && !images.contains(url) {
                                    // More permissive - accept any URL that looks like an image
                                    if isLikelyImageURL(url) {
                                        images.append(url)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return ForumPost(
            pid: pid,
            author: author,
            authorUid: authorUid,
            authorAvatar: authorAvatar,
            postDate: postDate,
            content: content,
            images: images,
            floorNumber: floorNumber,
            title: nil,
            viewCount: 0
        )
    }

    // MARK: - Login Page Parsing

    static func parseLoginPage(_ html: String) throws -> LoginFormData {
        let doc = try SwiftSoup.parse(html)

        // Extract formhash
        let formhashElement = try doc.select("input[name='formhash']").first()
        let formhash = try formhashElement?.attr("value") ?? ""

        // Extract default question id
        let questionSelect = try doc.select("select[name='questionid'], #questionid").first()
        let questionIdString = try questionSelect?.attr("value") ?? "0"
        let questionId = Int(questionIdString) ?? 0

        guard !formhash.isEmpty else {
            throw NetworkError.parsingFailed("Failed to extract formhash from login page")
        }

        return LoginFormData(formhash: formhash, questionId: questionId)
    }

    // MARK: - Helper Methods

    static func extractFormhash(_ html: String) -> String? {
        guard let data = try? SwiftSoup.parse(html) else { return nil }
        return try? data.select("input[name='formhash']").first()?.attr("value")
    }

    private static func extractFid(from element: Element) throws -> Int {
        let link = try element.select("a[href*='forumdisplay.php?fid=']").first()
        let href = try link?.attr("href") ?? ""
        return extractFidFromURL(href)
    }

    private static func extractFidFromURL(_ url: String) -> Int {
        guard let range = url.range(of: "fid=") else { return 0 }
        let fidStart = url.index(range.upperBound, offsetBy: 0)
        let fidEnd = url[range.upperBound...].firstIndex(of: "&") ?? url.endIndex
        let fidString = String(url[fidStart..<fidEnd])
        return Int(fidString) ?? 0
    }

    private static func extractUidFromURL(_ url: String) -> Int {
        guard let range = url.range(of: "uid=") else { return 0 }
        let uidStart = url.index(range.upperBound, offsetBy: 0)
        let uidEnd = url[range.upperBound...].firstIndex(of: "&") ?? url.endIndex
        let uidString = String(url[uidStart..<uidEnd])
        return Int(uidString) ?? 0
    }

    /// Checks if a URL is likely to point to an image based on common patterns
    private static func isLikelyImageURL(_ url: String) -> Bool {
        let lowercasedURL = url.lowercased()

        // Common image file extensions
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".ico"]
        for ext in imageExtensions {
            if lowercasedURL.contains(ext) {
                return true
            }
        }

        // Common image hosting patterns (Discuz attachments, CDNs, etc.)
        let imagePatterns = [
            "attachment",
            "image.php",
            "attachments",
            "album",
            "picture",
            "photo",
            "img",
            "/img/",
            "/pic/",
            "/image/"
        ]

        for pattern in imagePatterns {
            if lowercasedURL.contains(pattern) {
                return true
            }
        }

        return false
    }

    private static func extractTidFromURL(_ url: String) -> Int? {
        guard let range = url.range(of: "tid=") else { return nil }
        let tidStart = url.index(range.upperBound, offsetBy: 0)
        let tidEnd = url[range.upperBound...].firstIndex(of: "&") ?? url.endIndex
        let tidString = String(url[tidStart..<tidEnd])
        return Int(tidString)
    }

    private static func extractForumName(from element: Element) throws -> String {
        let link = try element.select("a[href*='forumdisplay.php?fid=']").first()
        return try link?.text() ?? ""
    }

    private static func extractForumDescription(from element: Element) throws -> String {
        // Try class-based selectors first
        if let desc = try? element.select(".forumdesc, .description").first() {
            let text = try desc.text()
            if !text.isEmpty {
                return text
            }
        }

        // Fallback: try to find <p> tag after <h2> with forum link
        if let h2 = try? element.select("h2").first(),
           let p = try? h2.nextElementSibling(),
           p.tagName() == "p" {
            return try p.text()
        }

        // Try any <p> tag within the element
        if let p = try? element.select("p").first() {
            let text = try p.text()
            // Avoid returning empty or very short text that might not be description
            if text.count > 5 {
                return text
            }
        }

        return ""
    }

    private static func extractThreadCount(from element: Element) throws -> Int {
        let countElement = try element.select(".ts, [class*='thread']").first()
        let countText = try countElement?.text() ?? "0"
        return Int(countText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static func extractPostCount(from element: Element) throws -> Int {
        let countElement = try element.select(".ts, [class*='post']").first()
        let countText = try countElement?.text() ?? "0"
        return Int(countText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private static func extractLastPostAuthor(from text: String) -> String {
        let components = text.components(separatedBy: " ")
        for component in components.reversed() {
            if !component.isEmpty && component != "by" {
                return component
            }
        }
        return ""
    }

    private static func extractLastPostDate(from text: String) -> String {
        let pattern = "\\d{4}-\\d{2}-\\d{2}"
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[range])
        }
        return text
    }

    private static func extractPageInfo(from text: String) -> (current: Int, total: Int) {
        let parts = text.components(separatedBy: " ")
        var currentPage = 1
        var totalPages = 1

        for part in parts {
            if part.hasPrefix("1/") || part.hasSuffix("/1") {
                let pages = part.replacingOccurrences(of: "/", with: "")
                totalPages = Int(pages) ?? 1
            }
            if let pageNum = Int(part), pageNum > 0 {
                currentPage = pageNum
            }
        }

        return (currentPage, totalPages)
    }

    // MARK: - Private Messages Parsing

    static func parsePrivateMessages(_ data: Data) throws -> [PrivateMessage] {
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode PM HTML")
        }

        let doc = try SwiftSoup.parse(decodedHTML)
        var messages: [PrivateMessage] = []

        // Parse PM list items - format: <li id="pm_数字">
        let pmItems = try doc.select("li[id^='pm_']")

        for item in pmItems {
            if let pm = try? parsePMLiItem(item) {
                messages.append(pm)
            }
        }

        return messages
    }

    private static func parsePMLiItem(_ item: Element) throws -> PrivateMessage? {
        // Extract pmid from id: "pm_10287144"
        let id = try item.attr("id")
        guard id.hasPrefix("pm_") else { return nil }

        let pmidString = String(id.dropFirst(3))
        guard let pmid = Int(pmidString) else { return nil }

        // Check if new message
        let isNew = item.hasClass("new") || id.contains("_new")

        // Extract from user info from avatar link
        var fromUid = 0
        var fromUsername = "未知用户"
        var fromAvatar: String? = nil

        if let avatarLink = try? item.select("a.avatar").first() {
            if let href = try? avatarLink.attr("href") {
                fromUid = extractUidFromURL(href)
            }
            if let avatarImg = try? avatarLink.select("img").first() {
                fromAvatar = try avatarImg.attr("src")
            }
        }

        // Extract username from cite
        if let cite = try? item.select("p.cite a").first() {
            fromUsername = try cite.text()
            if let href = try? cite.attr("href") {
                fromUid = extractUidFromURL(href)
            }
        }

        // Extract date from cite
        //
        // `<p class="cite"><cite><a>用户名</a></cite>昨天 14:20</p>`
        // 时间格式并不统一：近期是相对时间（"昨天 14:20"），较早的是绝对时间，
        // 且月/日不补零（"2025-4-10 21:33"）。原来的正则要求
        // `\d{4}-\d{2}-\d{2}`，两种都匹配不上，messageDate 因此恒为空。
        //
        // 与其枚举格式，不如把 p.cite 的文本减去 <cite> 里的用户名，
        // 剩下的就是时间，对任何格式都成立。
        var messageDate = ""
        if let cite = try? item.select("p.cite").first() {
            var text = (try? cite.text()) ?? ""
            if let nameEl = try? cite.select("cite").first(),
               let name = try? nameEl.text(),
               !name.isEmpty,
               let nameRange = text.range(of: name) {
                text.removeSubrange(nameRange)
            }
            messageDate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract subject/title
        var subject = ""
        if let subjectEl = try? item.select(".pm_subject, .subject, p.subject").first() {
            subject = try subjectEl.text()
        }

        // Extract summary
        var summary = ""
        if let summaryEl = try? item.select(".summary, .content, p.summary").first() {
            summary = try summaryEl.text()
        }

        // If no subject found, use first part of summary
        if subject.isEmpty && !summary.isEmpty {
            let components = summary.components(separatedBy: " ")
            subject = components.prefix(5).joined(separator: " ")
            if components.count > 5 {
                subject += "..."
            }
        }

        // Determine folder based on URL or class
        var folder: PrivateMessage.PMFolder = .inbox
        if let moreLink = try? item.select("p.more a").first(),
           let href = try? moreLink.attr("href") {
            if href.contains("folder=outbox") {
                folder = .outbox
            }
        }

        return PrivateMessage(
            id: pmid,
            pmid: pmid,
            fromUid: fromUid,
            fromUsername: fromUsername,
            fromAvatar: fromAvatar,
            toUid: 0,
            subject: subject,
            summary: summary,
            messageDate: messageDate,
            isNew: isNew,
            folder: folder
        )
    }

    // MARK: - PM Detail Parsing

    static func parsePMDetail(_ data: Data) throws -> PMDetail {
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode PM Detail HTML")
        }

        let doc = try SwiftSoup.parse(decodedHTML)

        // Extract other user info from the header
        var fromUid = 0
        var fromUsername = "未知用户"

        if let userLink = try? doc.select(".itemtitle .left strong").first() {
            fromUsername = try userLink.text()
        }

        // Extract fromUid from the URL in the page
        if let pmform = try? doc.select("#pmform").first(),
           let action = try? pmform.attr("action"),
           let uidRange = action.range(of: "uid=") {
            let uidStart = action.index(uidRange.upperBound, offsetBy: 0)
            let uidEnd = action[uidStart...].firstIndex(of: "&") ?? action.endIndex
            let uidString = String(action[uidStart..<uidEnd])
            fromUid = Int(uidString) ?? 0
        }

        // Parse messages
        var messages: [PMMessage] = []

        // Parse message items in the PM list - format: <li id="pm_数字" class="s_clear [self]">
        let pmItems = try doc.select("li[id^='pm_']")

        for item in pmItems {
            if let pmMessage = try? parsePMMessageItem(item) {
                messages.append(pmMessage)
            }
        }

        // Extract pagination info
        var currentPage = 1
        var totalPages = 1

        return PMDetail(
            fromUid: fromUid,
            fromUsername: fromUsername,
            messages: messages,
            currentPage: currentPage,
            totalPages: totalPages,
            formhash: extractFormhashFromPMForm(doc: doc)
        )
    }

    private static func extractFormhashFromPMForm(doc: Document) -> String? {
        if let formhashInput = try? doc.select("input[name='formhash']").first() {
            return try? formhashInput.attr("value")
        }
        return nil
    }

    private static func parsePMMessageItem(_ item: Element) throws -> PMMessage? {
        // Extract pmid from id: "pm_10287145"
        let id = try item.attr("id")
        guard id.hasPrefix("pm_") else { return nil }

        let pmidString = String(id.dropFirst(3))
        guard let pmid = Int(pmidString) else { return nil }

        // Check if this is a message sent by self
        let isSelf = item.hasClass("self")

        // Extract author info
        var author = "未知用户"
        var authorUid = 0
        var authorAvatar: String? = nil

        // Extract from cite
        if let cite = try? item.select("p.cite").first() {
            if let authorLink = try? cite.select("cite a, cite").first() {
                author = try authorLink.text()
                if let href = try? authorLink.attr("href") {
                    authorUid = extractUidFromURL(href)
                }
            }
        }

        // Extract avatar
        if let avatarLink = try? item.select("a.avatar").first() {
            if let avatarImg = try? avatarLink.select("img").first() {
                authorAvatar = try avatarImg.attr("src")
            }
        }

        // Extract date from cite
        var postDate = ""
        if let cite = try? item.select("p.cite").first() {
            let text = try cite.text()
            if let dateRange = text.range(of: "\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}", options: .regularExpression) {
                postDate = String(text[dateRange])
            }
        }

        // Extract content - use html() to preserve line breaks
        var content = ""
        if let summaryEl = try? item.select(".summary").first() {
            // Get HTML and convert <br> to newlines
            let htmlContent = try summaryEl.html()
            content = htmlContent.replacingOccurrences(of: "<br>", with: "\n")
                .replacingOccurrences(of: "<br/>", with: "\n")
                .replacingOccurrences(of: "<br />", with: "\n")
                .replacingOccurrences(of: "&nbsp;", with: " ")
            // Strip remaining HTML tags
            content = content.stripHTML()
        }

        return PMMessage(
            id: pmid,
            pmid: pmid,
            author: author,
            authorUid: authorUid,
            authorAvatar: authorAvatar,
            postDate: postDate,
            content: content,
            isSelf: isSelf
        )
    }

    // Helper method to extract formhash from PM detail
    static func extractFormhashFromPMForm(detail: PMDetail) -> String? {
        // This needs the raw HTML, so we'll fetch it separately
        return nil
    }

    // MARK: - Search Results Parsing

    static func parseSearchResults(_ data: Data) throws -> SearchDetail {
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode Search HTML")
        }

        let doc = try SwiftSoup.parse(decodedHTML)

        // Extract keyword and total results
        var keyword = ""
        var totalResults = 0

        if let resultHeader = try? doc.select(".searchlist h1 em").first() {
            let text = try resultHeader.text()
            // Format: "找到 "test" 相关主题 309 个"
            if let keywordRange = text.range(of: "\"[^\"]+\"", options: .regularExpression) {
                keyword = String(text[keywordRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            if let countRange = text.range(of: "\\d+ 个", options: .regularExpression) {
                let countStr = String(text[countRange]).replacingOccurrences(of: " 个", with: "")
                totalResults = Int(countStr) ?? 0
            }
        }

        // Extract pagination info
        var currentPage = 1
        var totalPages = 1

        if let pagination = try? doc.select(".pages strong").first()?.text() {
            currentPage = Int(pagination) ?? 1
        }
        let pageLinks = try? doc.select(".pages a[href*='page=']").array()
        if let lastPageLink = pageLinks?.last,
           let href = try? lastPageLink.attr("href"),
           let pageRange = href.range(of: "page=\\d+", options: .regularExpression) {
            let pageStr = String(href[pageRange]).replacingOccurrences(of: "page=", with: "")
            totalPages = Int(pageStr) ?? 1
        }

        // Parse search results
        var results: [SearchResult] = []

        // Each result is in a <tbody> containing a <tr>
        let tbodyElements = try doc.select("table.datatable tbody")

        for tbody in tbodyElements {
            if let result = try? parseSearchResultRow(tbody) {
                results.append(result)
            }
        }

        return SearchDetail(
            keyword: keyword,
            totalResults: totalResults,
            currentPage: currentPage,
            totalPages: totalPages,
            results: results
        )
    }

    private static func parseSearchResultRow(_ tbody: Element) throws -> SearchResult? {
        // Extract tid from viewthread link
        var tid: Int?
        var title = ""
        var forumName = ""
        var forumFid = 0
        var author = ""
        var authorUid = 0
        var postDate = ""
        var replyCount = 0
        var viewCount = 0
        var lastPostAuthor = ""
        var lastPostDate = ""

        // Title and tid from th.subject
        if let subjectTh = try? tbody.select("th.subject").first() {
            if let titleLink = try? subjectTh.select("a[href*='viewthread.php?tid=']").first() {
                title = try titleLink.text()
                if let href = try? titleLink.attr("href") {
                    tid = extractTidFromURL(href)
                }
            }
        }

        // Forum name and fid
        if let forumTd = try? tbody.select("td.forum").first() {
            forumName = try forumTd.text()
            if let forumLink = try? forumTd.select("a[href*='forumdisplay.php?fid=']").first() {
                if let href = try? forumLink.attr("href") {
                    forumFid = extractFidFromURL(href)
                }
            }
        }

        // Author info
        if let authorTd = try? tbody.select("td.author").first() {
            if let authorLink = try? authorTd.select("cite a[href*='space.php?uid=']").first() {
                author = try authorLink.text()
                if let href = try? authorLink.attr("href") {
                    authorUid = extractUidFromURL(href)
                }
            }
            if let dateEm = try? authorTd.select("em").first() {
                postDate = try dateEm.text()
            }
        }

        // Reply and view count
        if let numsTd = try? tbody.select("td.nums").first() {
            let text = try numsTd.text()
            // Format: "2 / 205"
            let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                replyCount = Int(parts[0].replacingOccurrences(of: ",", with: "")) ?? 0
                viewCount = Int(parts[1].replacingOccurrences(of: ",", with: "")) ?? 0
            }
        }

        // Last post info
        if let lastpostTd = try? tbody.select("td.lastpost").first() {
            if let lastpostCite = try? lastpostTd.select("cite").first() {
                if let authorLink = try? lastpostCite.select("a").first() {
                    lastPostAuthor = try authorLink.text()
                }
            }
            if let dateEm = try? lastpostTd.select("em").first() {
                if let dateLink = try? dateEm.select("a").first() {
                    lastPostDate = try dateLink.text()
                } else {
                    lastPostDate = try dateEm.text()
                }
            }
        }

        guard let threadId = tid, threadId > 0 else { return nil }

        return SearchResult(
            tid: threadId,
            title: title,
            forumName: forumName,
            forumFid: forumFid,
            author: author,
            authorUid: authorUid,
            postDate: postDate,
            replyCount: replyCount,
            viewCount: viewCount,
            lastPostAuthor: lastPostAuthor,
            lastPostDate: lastPostDate
        )
    }

    // MARK: - User Profile Parsing

    static func parseUserProfile(_ data: Data) throws -> ForumUser {
        let encodingsToTry: [String.Encoding] = [
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000631))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000630))),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x80000632))),
            .utf8,
            .windowsCP1252
        ]

        var html: String?
        for encoding in encodingsToTry {
            if let decoded = String(data: data, encoding: encoding) {
                html = decoded
                break
            }
        }

        guard let decodedHTML = html else {
            throw NetworkError.parsingFailed("Failed to decode User Profile HTML")
        }

        return try parseUserProfile(html: decodedHTML)
    }

    /// 解析已经解码好的 HTML（例如 WKWebView 的 `outerHTML`）。
    ///
    /// ⚠️ 这种场景**不要**再走上面的 Data 版本：把已解码的 String 转成
    /// `data(using: .utf8)` 再交给 GB18030 优先的解码器，会把 UTF-8 字节
    /// 当成 GB18030 解一遍。GB18030 几乎接受任意字节序列，所以这步必定
    /// "成功"却产出乱码，中文标签全部匹配不上。
    static func parseUserProfile(html decodedHTML: String) throws -> ForumUser {
        let doc = try SwiftSoup.parse(decodedHTML)

        // Extract username from h1 in profilecontent
        var username = ""
        if let h1 = try? doc.select("#profilecontent h1").first() {
            username = try h1.text().trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove online icon text if present
            if let range = username.range(of: "当前在线") {
                username = String(username[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Extract UID from script variable: discuz_uid = 717232
        //
        // 必须搜整篇文档：discuz_uid 是 <head> 里那段 script 定义的，
        // 原来只搜 doc.body() 永远匹配不到，uid 因此恒为 0。
        var uid = 0
        if let bodyHtml = try? doc.html() {
            let pattern = "discuz_uid\\s*=\\s*(\\d+)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(bodyHtml.startIndex..., in: bodyHtml)
                if let match = regex.firstMatch(in: bodyHtml, options: [], range: range) {
                    if let uidRange = Range(match.range(at: 1), in: bodyHtml) {
                        let uidStr = String(bodyHtml[uidRange])
                        uid = Int(uidStr) ?? 0
                    }
                }
            }
        }

        // Extract avatar
        var avatar: String?
        if let avatarImg = try? doc.select(".profile_side .avatar img").first() {
            avatar = try avatarImg.attr("src")
        }

        // Check if online (presence of online_buddy.gif)
        let isOnline = (try? doc.select(".online_buddy").first()) != nil

        // Extract gender
        var gender: String?
        if let genderRow = try? doc.select("#baseprofile table.formtable tr").first() {
            let text = try genderRow.text()
            if text.contains("男") {
                gender = "男"
            } else if text.contains("女") {
                gender = "女"
            }
        }

        // Extract QQ
        var qq: String?
        if let qqLink = try? doc.select("a[href*='wpa.qq.com']").first() {
            let href = try qqLink.attr("href")
            if let uinRange = href.range(of: "Uin=(\\d+)", options: .regularExpression) {
                qq = String(href[uinRange])
                    .replacingOccurrences(of: "Uin=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Extract MSN
        var msn: String?

        // Extract user group
        var userGroup = ""
        if let groupLink = try? doc.select(".blocktitle.lightlink a").first() {
            userGroup = try groupLink.text()
        }

        // Extract info from commonlist sections
        var registrationDate: String?
        var lastVisitDate: String?
        var lastPostDate: String?
        var registrationIP: String?
        var lastVisitIP: String?
        var postLevel: String?
        var readPermission = 0
        var totalPosts = 0
        var dailyAveragePosts: Double = 0
        var essencePosts = 0
        var pageViews = 0
        var totalOnlineHours: Double = 0
        var monthOnlineHours: Double = 0
        var credits = 0
        var prestige = 0
        var money = 0
        var sellerCredit = 0
        var buyerCredit = 0

        let commonLists = try doc.select("ul.commonlist")
        for list in commonLists {
            let text = try list.text()

            // Left side info (registration, last visit, etc.)
            if text.contains("注册日期") {
                if let range = text.range(of: "注册日期:\\s*(\\d{4}-\\d{2}-\\d{2})", options: .regularExpression) {
                    let match = String(text[range])
                    registrationDate = match.replacingOccurrences(of: "注册日期:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if text.contains("上次访问") {
                if let range = text.range(of: "上次访问:\\s*(\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2})", options: .regularExpression) {
                    let match = String(text[range])
                    lastVisitDate = match.replacingOccurrences(of: "上次访问:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if text.contains("最后发表") {
                if let range = text.range(of: "最后发表:\\s*(\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2})", options: .regularExpression) {
                    let match = String(text[range])
                    lastPostDate = match.replacingOccurrences(of: "最后发表:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if text.contains("注册 IP") {
                let ipPattern = "注册 IP:\\s*([\\d.]+)"
                if let range = text.range(of: ipPattern, options: .regularExpression) {
                    let match = String(text[range])
                    registrationIP = match.replacingOccurrences(of: "注册 IP:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if text.contains("上次访问 IP") {
                let ipPattern = "上次访问 IP:\\s*([\\d.]+)"
                if let range = text.range(of: ipPattern, options: .regularExpression) {
                    let match = String(text[range])
                    lastVisitIP = match.replacingOccurrences(of: "上次访问 IP:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Right side info (post level, posts, etc.)
            if text.contains("发帖数级别") {
                if let range = text.range(of: "发帖数级别:\\s*([^\\s]+)", options: .regularExpression) {
                    let match = String(text[range])
                    postLevel = match.replacingOccurrences(of: "发帖数级别:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    // Remove star images text
                    if let starIdx = postLevel?.range(of: "\\s*<img") {
                        postLevel = String(postLevel?[..<starIdx.lowerBound] ?? "")
                    }
                    postLevel = postLevel?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if text.contains("阅读权限") {
                if let range = text.range(of: "阅读权限:\\s*(\\d+)", options: .regularExpression) {
                    let match = String(text[range])
                    let permStr = match.replacingOccurrences(of: "阅读权限:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    readPermission = Int(permStr) ?? 0
                }
            }
            if text.contains("帖子:") {
                if let range = text.range(of: "帖子:\\s*(\\d+)", options: .regularExpression) {
                    let match = String(text[range])
                    let postsStr = match.replacingOccurrences(of: "帖子:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    totalPosts = Int(postsStr) ?? 0
                }
            }
            if text.contains("精华:") {
                if let range = text.range(of: "精华:\\s*(\\d+)", options: .regularExpression) {
                    let match = String(text[range])
                    let essenceStr = match.replacingOccurrences(of: "精华:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    essencePosts = Int(essenceStr) ?? 0
                }
            }
            if text.contains("页面访问量") {
                if let range = text.range(of: "页面访问量:\\s*([\\d,]+)", options: .regularExpression) {
                    let match = String(text[range])
                    let viewsStr = match.replacingOccurrences(of: "页面访问量:", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    pageViews = Int(viewsStr) ?? 0
                }
            }
            if text.contains("平均每日发帖") {
                if let range = text.range(of: "平均每日发帖:\\s*([\\d.]+)", options: .regularExpression) {
                    let match = String(text[range])
                    let avgStr = match.replacingOccurrences(of: "平均每日发帖:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    dailyAveragePosts = Double(avgStr) ?? 0
                }
            }
        }

        // Extract online time
        if let onlineTimeText = try? doc.select("#profilecontent p").last()?.text() {
            if let totalRange = onlineTimeText.range(of: "总计在线\\s*<em>([\\d.]+)</em>", options: .regularExpression) {
                let match = String(onlineTimeText[totalRange])
                let hoursStr = match.replacingOccurrences(of: "总计在线", with: "").replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                totalOnlineHours = Double(hoursStr) ?? 0
            }
            if let monthRange = onlineTimeText.range(of: "本月在线\\s*<em>([\\d.]+)</em>", options: .regularExpression) {
                let match = String(onlineTimeText[monthRange])
                let hoursStr = match.replacingOccurrences(of: "本月在线", with: "").replacingOccurrences(of: "<em>", with: "").replacingOccurrences(of: "</em>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                monthOnlineHours = Double(hoursStr) ?? 0
            }
        }

        // Extract credits
        //
        // 实际结构（4d4y / Discuz 7.2）：
        //   <h3 class="blocktitle lightlink">积分: 7</h3>
        //   <p>威望: 7 ,&nbsp;金钱: 0 </p>
        // 「积分」在 h3 自身，「威望 / 金钱」才在紧随其后的 <p> 里。
        //
        // 两个坑：
        // 1. 原来只取 nextElementSibling()，把 h3 自身漏掉了 → 积分恒为 0
        // 2. 页面里有 3 个 h3.blocktitle（用户组 / 积分 / 信用评价），
        //    .first() 取到的是「用户组: 初级会员」，必须逐个找含「积分:」的那个
        let creditsBlocks = (try? doc.select("#profilecontent h3.blocktitle")) ?? Elements()
        for header in creditsBlocks {
            var creditsText = (try? header.text()) ?? ""
            if let sibling = try? header.nextElementSibling(),
               let siblingText = try? sibling.text() {
                creditsText += " " + siblingText
            }

            guard creditsText.contains("积分:") || creditsText.contains("威望:") || creditsText.contains("金钱:") else {
                continue
            }

            if creditsText.contains("积分:") {
                let creditsPattern = "积分:\\s*(\\d+)"
                if let range = creditsText.range(of: creditsPattern, options: .regularExpression) {
                    let match = String(creditsText[range])
                    credits = Int(match.replacingOccurrences(of: "积分:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
            }
            if creditsText.contains("威望:") {
                if let range = creditsText.range(of: "威望:\\s*(\\d+)", options: .regularExpression) {
                    let match = String(creditsText[range])
                    prestige = Int(match.replacingOccurrences(of: "威望:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
            }
            if creditsText.contains("金钱:") {
                if let range = creditsText.range(of: "金钱:\\s*(\\d+)", options: .regularExpression) {
                    let match = String(creditsText[range])
                    money = Int(match.replacingOccurrences(of: "金钱:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
            }
            break
        }

        // Extract credit ratings
        if let creditText = try? doc.select("#profilecontent").first()?.text() {
            if creditText.contains("卖家信用评价:") {
                let pattern = "卖家信用评价:\\s*(\\d+)"
                if let range = creditText.range(of: pattern, options: .regularExpression) {
                    let match = String(creditText[range])
                    sellerCredit = Int(match.replacingOccurrences(of: "卖家信用评价:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
            }
            if creditText.contains("买家信用评价:") {
                let pattern = "买家信用评价:\\s*(\\d+)"
                if let range = creditText.range(of: pattern, options: .regularExpression) {
                    let match = String(creditText[range])
                    buyerCredit = Int(match.replacingOccurrences(of: "买家信用评价:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
            }
        }

        return ForumUser(
            uid: uid,
            username: username,
            avatar: avatar,
            isOnline: isOnline,
            gender: gender,
            qq: qq,
            msn: msn,
            userGroup: userGroup,
            registrationDate: registrationDate,
            lastVisitDate: lastVisitDate,
            lastPostDate: lastPostDate,
            registrationIP: registrationIP,
            lastVisitIP: lastVisitIP,
            postLevel: postLevel,
            readPermission: readPermission,
            totalPosts: totalPosts,
            dailyAveragePosts: dailyAveragePosts,
            essencePosts: essencePosts,
            pageViews: pageViews,
            totalOnlineHours: totalOnlineHours,
            monthOnlineHours: monthOnlineHours,
            credits: credits,
            prestige: prestige,
            money: money,
            sellerCredit: sellerCredit,
            buyerCredit: buyerCredit
        )
    }

    // Helper to strip HTML tags
    private static func stripHTML(_ html: String) -> String {
        // Simple regex to strip HTML tags
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
    }
}

// String extension for stripping HTML
extension String {
    func stripHTML() -> String {
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }
}
