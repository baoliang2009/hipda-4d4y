# 登录问题修复总结

## 问题诊断

从日志分析发现：
```
[LoginManager] No saved cookies found
[Profile] isLoggedIn: false
```

**根本原因**：登录成功后，Cookie 没有被保存到 UserDefaults，导致应用重启后无法恢复登录状态。

## 问题分析

### 登录流程有 3 个路径：

1. **用户名密码登录** (`LoginViewController:424-440`)
   - ❌ 只设置了 `isLoggedIn = true`
   - ❌ 没有调用 `saveCookies()`

2. **WebView 登录（无 forumListCompletion）** (`LoginViewController:779-799`)
   - ✅ 同步了 Cookie 到 HTTPCookieStorage
   - ❌ 但没有保存到 UserDefaults

3. **WebView 登录（有 forumListCompletion）** (`LoginViewController:1226`)
   - ✅ 调用了 `saveCookies()`

### 为什么第 3 个路径有效？

只有当 `extractForumListHTML` 被调用时才会保存 Cookie（第 1226 行），但这个方法只在特定情况下被调用。

## 修复方案

在所有登录成功的路径都添加 `LoginManager.shared.saveCookies()` 调用：

### 修改 1: 用户名密码登录成功后保存 Cookie
**文件**: `Sources/ViewControllers/LoginViewController.swift:436`

```swift
if success {
    if self.rememberMeSwitch.isOn {
        LoginManager.shared.saveCredentials(...)
    }
    LoginManager.shared.isLoggedIn = true

    // ✅ 新增：保存 Cookie
    LoginManager.shared.saveCookies()
    print("[Login] Saved cookies after successful login")

    // Clear forum list cache so it refreshes with logged-in data
    CacheManager.shared.clearCache(forKey: CacheManager.CacheKeys.forumList())
    ...
}
```

### 修改 2: syncCookiesAndComplete 中保存 Cookie
**文件**: `Sources/ViewControllers/LoginViewController.swift:789-799`

```swift
private func syncCookiesAndComplete(webView: WKWebView) {
    syncCookiesToSharedStorage(from: webView) { [weak self] hasCookies in
        guard let self = self else { return }
        print("[Login] Cookie sync result: hasCookies=\(hasCookies)")

        // ✅ 新增：保存 Cookie 到 UserDefaults
        if hasCookies {
            LoginManager.shared.saveCookies()
            print("[Login] Saved cookies to UserDefaults for persistence")
        }

        if self.forumListCompletion != nil {
            self.extractForumListHTML(from: webView)
        } else {
            print("[Login] Login completed, notifying delegate")
            self.delegate?.loginViewControllerDidLogin(self)
            self.cleanup()
        }
    }
}
```

### 修改 3: handleLoginSuccess 中保存 Cookie
**文件**: `Sources/ViewControllers/LoginViewController.swift:1142`

```swift
private func handleLoginSuccess(webView: WKWebView) {
    updateLoadingMessage("登录成功，正在同步数据...")
    syncCookiesToSharedStorage(from: webView) { [weak self] hasCookies in
        guard let self = self else { return }

        print("[Login] After cookie sync - hasCookies: \(hasCookies)")

        if hasCookies {
            // ✅ 新增：保存 Cookie 到 UserDefaults
            LoginManager.shared.saveCookies()
            print("[Login] Saved cookies after login success")

            // First go to memcp.php to extract UID
            print("[Login] Proceeding to memcp.php to get UID...")
            let memcpURL = URL(string: "https://www.4d4y.com/forum/memcp.php")!
            webView.load(URLRequest(url: memcpURL))
        } else {
            self.loginCompletion?(false, "登录失败，未获取到有效的会话")
            self.cleanup()
        }
    }
}
```

## 验证

修复后，所有 `saveCookies()` 调用位置：
1. ✅ Line 436: 用户名密码登录成功后
2. ✅ Line 672: Cookie 同步后（已存在）
3. ✅ Line 790: syncCookiesAndComplete 中
4. ✅ Line 1142: handleLoginSuccess 中
5. ✅ Line 1241: extractForumListHTML 中（已存在）

## 预期效果

修复后：
1. ✅ 用户登录成功后，Cookie 会被保存到 UserDefaults
2. ✅ 应用重启时，`LoginManager.restoreCookies()` 会恢复 Cookie
3. ✅ 用户不需要重复登录
4. ✅ `[LoginManager] No saved cookies found` 日志不会再出现

## 测试步骤

1. 清空应用数据（删除并重装）
2. 启动应用，登录账号
3. 观察日志，应该看到：
   ```
   [Login] Saved cookies after successful login
   [LoginManager] Saved X cookies with full attributes
   ```
4. 完全退出应用
5. 重新启动应用
6. 观察日志，应该看到：
   ```
   [LoginManager] Restored X/X cookies
   [Profile] isLoggedIn: true
   ```
7. ✅ 用户应该保持登录状态，不需要重新登录

## 相关文件

- `Sources/ViewControllers/LoginViewController.swift` - 登录界面（修改）
- `Sources/LoginManager.swift` - Cookie 管理（未修改）
- `Sources/Network/NetworkManager.swift` - 网络请求（未修改）

## 注意事项

1. Cookie 有效期为 7 天（由服务器设置）
2. `LoginManager.restoreCookies()` 会自动跳过过期的 Cookie
3. 如果 Cookie 过期，用户需要重新登录
4. Cookie 存储在 UserDefaults 的 `forum_cookies` 键中
