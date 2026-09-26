import Foundation

/// 帖子收藏管理器（本地，UserDefaults）。
///
/// 与项目已有的「版块收藏」(`ForumManager`) 一致，走纯本地存储：
/// 不依赖论坛服务端接口，离线可用，不受 Cloudflare/网络影响。
final class FavoriteManager {
    static let shared = FavoriteManager()

    /// 收藏变化时发出，首页据此刷新（详情页收藏后返回首页能即时看到）
    static let didChangeNotification = Notification.Name("FavoriteManager.didChange")

    private let storageKey = "favorite_threads_data"

    private init() {}

    /// 全部收藏，最近收藏在前
    var favorites: [FavoriteThread] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([FavoriteThread].self, from: data) else {
            return []
        }
        return list.sorted { $0.favoritedAt > $1.favoritedAt }
    }

    /// 收藏的帖子（按收藏时间倒序），首页直接展示
    var favoriteThreads: [ForumThread] {
        favorites.map { $0.thread }
    }

    func isFavorited(tid: Int) -> Bool {
        favorites.contains { $0.thread.tid == tid }
    }

    /// 加入收藏（已存在则更新为最新数据 + 刷新收藏时间置顶）
    func add(_ thread: ForumThread) {
        var list = favorites.filter { $0.thread.tid != thread.tid }
        list.append(FavoriteThread(thread: thread, favoritedAt: Date()))
        save(list)
    }

    func remove(tid: Int) {
        let list = favorites.filter { $0.thread.tid != tid }
        save(list)
    }

    /// 切换收藏状态，返回切换后是否为「已收藏」
    @discardableResult
    func toggle(_ thread: ForumThread) -> Bool {
        if isFavorited(tid: thread.tid) {
            remove(tid: thread.tid)
            return false
        } else {
            add(thread)
            return true
        }
    }

    private func save(_ list: [FavoriteThread]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
