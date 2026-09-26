import Foundation

/// 一条收藏的帖子。
///
/// 直接内嵌完整的 `ForumThread`，这样首页展示和点击跳转都能复用现有的
/// `ThreadDetailViewController(thread:)`，无需再从网络补数据。
/// `favoritedAt` 仅用于「最近收藏在前」的排序。
struct FavoriteThread: Codable {
    let thread: ForumThread
    let favoritedAt: Date
}
