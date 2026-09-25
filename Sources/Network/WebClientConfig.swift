import Foundation

/// URLSession 与 WKWebView 共用的浏览器标识。
///
/// **必须保持一致**：Cloudflare 签发的 `cf_clearance` 与 User-Agent 强绑定。
/// WKWebView 通过 Turnstile 验证后拿到的 clearance，如果 URLSession 用另一个 UA
/// 去携带，Cloudflare 会判定不匹配并直接拒绝，表现为原生请求持续 403
/// （响应头 `cf-mitigated: challenge`）。
///
/// 之前 NetworkManager 写死 Chrome/131，而各个 WebView 写死 Chrome/147，
/// 同步过去的 clearance 从一开始就是无效的。
enum WebClientConfig {

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"

    /// 与上面 UA 配套的 Client Hints。
    /// 服务端在 `critical-ch` 响应头里明确点名要这些字段，缺失会让 Cloudflare
    /// 更倾向于下发挑战。取值必须和 userAgent 里的版本号对得上。
    private static let secChUa = "\"Google Chrome\";v=\"147\", \"Chromium\";v=\"147\", \"Not_A Brand\";v=\"24\""
    private static let secChUaMobile = "?0"
    private static let secChUaPlatform = "\"macOS\""

    /// 给原生请求补齐浏览器特征头，使其与 WebView 的指纹尽量一致
    static func applyBrowserHeaders(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(secChUa, forHTTPHeaderField: "sec-ch-ua")
        request.setValue(secChUaMobile, forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue(secChUaPlatform, forHTTPHeaderField: "sec-ch-ua-platform")
    }
}

/// 判定一个已加载的页面当前处于什么状态。
///
/// 不能靠"页面里有没有某段提示文字"来识别 Cloudflare 拦截页：
/// 文案会变（实测是「正在验证您是否是真人」而不是「正在进行安全验证」），
/// 类名每次随机混淆（jvHs1 / PqVE5 …），`cf-turnstile` 只在挂件注入的一瞬间存在。
/// 稳定的负向标志只有 `window._cf_chl_opt`；
/// 而判断"已经过关"必须**正向确认**目标页到位（Discuz 每页都会定义 `discuz_uid`），
/// 否则"没匹配到拦截页关键词"会被误判成"验证已通过"。
enum ForumPageProbe {

    struct State {
        /// 仍停留在 Cloudflare 拦截页
        var isChallenge = false
        /// 已经是真正的 Discuz 页面
        var isDiscuzPage = false
        var formhash = ""
        var uid = 0
        var hasLoginForm = false

        /// 真实论坛页面已就绪
        var isReady: Bool { !isChallenge && isDiscuzPage }
    }

    static let javaScript = #"""
    (function() {
        var body = document.body;
        var text = body ? body.innerText.substring(0, 300) : '';
        var isChallenge = !!window._cf_chl_opt
            || !!document.getElementById('challenge-error-text')
            || !!document.getElementById('challenge-form')
            || !!document.getElementById('cf-challenge-running')
            || !!document.querySelector('.cf-turnstile, [name="cf-turnstile-response"]')
            || /just a moment|checking your browser|正在验证您是否是真人|正在进行安全验证/i.test(document.title + ' ' + text);

        var isDiscuz = (typeof discuz_uid !== 'undefined');
        var formhashEl = document.querySelector('input[name=formhash]');

        return {
            isChallenge: isChallenge,
            isDiscuzPage: isDiscuz,
            formhash: formhashEl ? formhashEl.value : '',
            uid: isDiscuz ? Number(discuz_uid) || 0 : 0,
            hasLoginForm: !!document.getElementById('loginform')
        };
    })();
    """#

    /// 解析 JS 返回值。取不到结果时一律按"仍在验证中"处理，
    /// 交给调用方继续等，绝不能当成已通过。
    static func parse(_ result: Any?) -> State {
        var state = State()
        guard let dict = result as? [String: Any] else {
            state.isChallenge = true
            return state
        }
        state.isChallenge = dict["isChallenge"] as? Bool ?? false
        state.isDiscuzPage = dict["isDiscuzPage"] as? Bool ?? false
        state.formhash = dict["formhash"] as? String ?? ""
        state.uid = dict["uid"] as? Int ?? 0
        state.hasLoginForm = dict["hasLoginForm"] as? Bool ?? false
        return state
    }
}
