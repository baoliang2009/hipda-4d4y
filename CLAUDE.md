# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# FourD4Y iOS App

## 项目概述

iOS 客户端应用，连接至 4D4Y 论坛 (https://www.4d4y.com)。论坛采用 Discuz! 7.2，使用 GBK 编码。

## 技术栈

- **UI框架**: UIKit + WebKit (WKWebView)
- **网络库**: URLSession (通过 NetworkManager 单例管理)
- **图片加载**: SDWebImage
- **HTML解析**: SwiftSoup
- **登录凭证**: 存储在 UserDefaults + HTTPCookieStorage

## 项目结构

```
Sources/
├── AppDelegate.swift
├── MainViewController.swift
├── ForumManager.swift              # 论坛板块管理 (UserDefaults 存储)
├── LoginManager.swift              # 登录认证 (JavaScript 注入)
├── Network/
│   └── NetworkManager.swift        # 网络请求 + HTML 解析入口
├── Parser/
│   └── ForumHTMLParser.swift      # HTML 解析 (SwiftSoup, GBK 编码)
├── Managers/
│   ├── CacheManager.swift         # 磁盘缓存 (5分钟过期, 50MB上限)
│   └── ReadTracker.swift          # 已读帖子追踪
├── Models/                         # Codable 数据模型
│   ├── Forum.swift, ForumThread.swift, ForumPost.swift
│   ├── ThreadDetail.swift, SearchResult.swift
│   ├── ForumUser.swift, PrivateMessage.swift, PMDetail.swift
├── ViewControllers/               # UIKit 视图控制器
│   ├── MainTabBarController.swift, HomeViewController.swift
│   ├── ForumListViewController.swift, ThreadListViewController.swift
│   ├── ThreadDetailViewController.swift, ReplyViewController.swift
│   ├── NewThreadViewController.swift, LoginViewController.swift
│   ├── SearchViewController.swift, ProfileViewController.swift
│   ├── PMListViewController.swift, PMDetailViewController.swift
│   └── NotificationsViewController.swift, ExploreViewController.swift
└── Views/
    ├── ThreadCell.swift
    └── Theme.swift
```

## 构建

```bash
xcodegen generate        # 生成 .xcodeproj
xcodebuild -project FourD4Y.xcodeproj -scheme FourD4Y -configuration Debug build
```

依赖: SwiftSoup (HTML解析), SDWebImage (图片加载), CommonCrypto (MD5)

## 核心架构

### Cookie 认证同步
- URLSession 和 WKWebView 共享 `HTTPCookieStorage.shared`
- `LoginManager.restoreCookies()` 在启动时恢复 Cookie
- 登录通过 WKWebView JavaScript 注入执行（不是 URLSession），以确保 Cookie 同步

### HTML 解析策略
- `ForumHTMLParser` 使用 SwiftSoup 解析所有页面
- 编码尝试顺序: GB18030 → GB2312 → UTF-8 → WindowsCP1252
- 缓存: `CacheManager` 提供 5 分钟过期的磁盘缓存

### Cloudflare：被拦的是 WebView，不是原生请求

这一点与直觉相反，改动网络层前务必先读：

- **URLSession 是通的**。Apple 网络栈的 TLS 指纹被 Cloudflare 放行，直接返回 200 +
  真实 Discuz 页面。（注意：用 curl 在 Mac 上复现会得到 403，那是 curl 自身的
  OpenSSL 指纹被拦，不代表 App 的行为。）
- **WKWebView 会被拦**。Cloudflare 对它下发 Turnstile 托管质询，且**过不去**：
  挑战页每 ~45 秒自我刷新一次，turnstile iframe 反复 `-999`，等 180 秒依然
  `challenge=true`。

因此：

- **登录走原生** (`NetworkManager.nativeLogin`)，WebView 流程仅作兜底
- 取 uid 等只读信息一律走原生，不要用 WebView
- UA 必须全局一致（`WebClientConfig.userAgent`），POST 表单必须按 **GBK** 逐字节
  百分号编码，否则中文用户名/安全提问答案会乱码

### 发帖/回复/附件提交流程（已全部原生化）
- **已改为原生**（URLSession），旧的 WKWebView + `form.submit()` 方案已废弃：WebView 被
  Cloudflare Turnstile 拦死，formhash 根本取不到，发帖/回复名存实亡，图片也因 uploadHash
  拿不到而永远走"纯文本发帖"分支。
- 表单结构已对着真实登录后的页面核对（`NetworkManager` 里有注释）：
  - 取表单：GET `post.php?action=reply&tid=` / `post.php?action=newthread&fid=`，
    正则解析 `formhash`（可能是隐藏 input，也可能只出现在链接的 `?formhash=`）、
    `posttime`、上传用的 `hash`（`name="hash"`）、`fid`。
  - 回复提交：POST `post.php?action=reply&fid=&tid=&extra=&replysubmit=yes`
  - 发帖提交：POST `post.php?action=newthread&fid=&extra=&topicsubmit=yes`
  - body 字段：`formhash / posttime / wysiwyg=0 / subject / message`（发帖另加 `typeid / tags`），
    **必须按 GBK 逐字节百分号编码**（`gbkPercentEncoded`），否则中文乱码。
  - 成功判定：Discuz 成功后跳转 `viewthread.php`（ASCII 可靠）；否则尽量认中文错误提示。
- 图片附件：`misc.php?action=swfupload&operation=upload&simple=1&type=image`，
  multipart 带 `uid / hash / Filedata`，返回纯 `aid`。上传成功后附件挂在
  (uid, hash) 会话待处理列表里，提交发帖/回复时自动关联；正文追加
  `[attachimg]aid[/attachimg]` 控制内联显示位置。
- 排障提示：命令行 `swift` 脚本的 URLSession 同样能过 Cloudflare（Apple TLS 指纹），
  可用来只读抓取真实页面核对表单；但**不要手动设 `Accept-Encoding`**——一旦手设，
  URLSession 就不再自动解压，CF 强制返回的 brotli 得自己解。App 内不设该头，自动解压正常。

## 论坛 URL

- 首页: `https://www.4d4y.com/forum/`
- 板块: `forumdisplay.php?fid={fid}`
- 帖子: `viewthread.php?tid={tid}`
- 发帖: `post.php?action=newthread&fid={fid}`
- 回复: `post.php?action=reply&tid={tid}&reppost={pid}`

## 编码规范

### JavaScript 字符串
Swift 中嵌入 JavaScript 必须用原始字符串：

```swift
// 正确
webView.evaluateJavaScript(#"""
    var regex = /<option[^>]*value="([^"]*)"[^>]*>([^<]*)<\/option>/g;
"""#)

// 错误 - \n \r 等会被 Swift 解析
webView.evaluateJavaScript("""
    var regex = /<option[^>]*value="([^"]*)"[^>]*>([^<]*)<\\/option>/g;
""")
```

## 常见问题

### Cookie 同步
- 关键 Cookie: `cdb_auth`, `cdb_sid`, `cdb_cookietime`
- URLSession 和 WKWebView 共享 `HTTPCookieStorage.shared`
- 启动时 `LoginManager.restoreCookies()` 恢复 Cookie

### formhash
- 每次进入发帖页面获取新的 formhash
- 必须从页面提取，不能缓存

### typeid 分类
- 每个板块的分类不同，从 `<select id="typeid">` 提取
- 某些板块 JS 动态渲染，需在 `didFinish` 后延迟 1 秒再提取

### Cloudflare
- WKWebView 自动处理
