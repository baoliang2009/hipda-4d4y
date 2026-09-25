import Foundation

class CacheManager {
    static let shared = CacheManager()

    private let cacheDirectory: URL
    private let cacheExpiration: TimeInterval = 5 * 60 // 5 minutes default
    private let maxCacheSize: Int = 50 * 1024 * 1024 // 50MB max cache

    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("FourD4YCache", isDirectory: true)

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Clean up old cache on init
        cleanupOldCache()
    }

    // MARK: - Save Cache

    func save<T: Encodable>(_ object: T, forKey key: String, expiresIn: TimeInterval? = nil) {
        let fileURL = cacheFileURL(for: key)

        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: fileURL)

            // Update metadata with custom expiration
            let expiration = expiresIn ?? cacheExpiration
            saveMetadata(forKey: key, data: data, expiresIn: expiration)

            print("[Cache] Saved: \(key) (\(data.count) bytes, expires in \(Int(expiration))s)")

            // Check and enforce cache size limit
            enforceCacheSizeLimit()
        } catch {
            print("[Cache] Failed to save \(key): \(error)")
        }
    }

    // MARK: - Load Cache

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        let fileURL = cacheFileURL(for: key)

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Cache] Not found: \(key)")
            return nil
        }

        // Check if expired
        guard !isExpired(forKey: key) else {
            print("[Cache] Expired: \(key)")
            clearCache(forKey: key)
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let object = try JSONDecoder().decode(type, from: data)
            print("[Cache] Loaded: \(key)")
            return object
        } catch {
            print("[Cache] Failed to load \(key): \(error)")
            // Clear corrupted cache
            clearCache(forKey: key)
            return nil
        }
    }

    // MARK: - Cache Info

    func isExpired(forKey key: String) -> Bool {
        guard let metadata = loadMetadata(forKey: key),
              let timestamp = metadata["timestamp"] as? TimeInterval,
              let expiration = metadata["expiration"] as? TimeInterval else {
            return true
        }

        return Date().timeIntervalSince1970 - timestamp > expiration
    }

    func getCacheAge(forKey key: String) -> String? {
        guard let metadata = loadMetadata(forKey: key),
              let timestamp = metadata["timestamp"] as? TimeInterval else {
            return nil
        }

        let age = Date().timeIntervalSince1970 - timestamp
        if age < 60 {
            return "\(Int(age)) 秒前"
        } else if age < 3600 {
            return "\(Int(age / 60)) 分钟前"
        } else {
            return "\(Int(age / 3600)) 小时前"
        }
    }

    // MARK: - Clear Cache

    func clearCache(forKey key: String) {
        let fileURL = cacheFileURL(for: key)
        try? FileManager.default.removeItem(at: fileURL)

        let metadataURL = metadataFileURL(for: key)
        try? FileManager.default.removeItem(at: metadataURL)

        print("[Cache] Cleared: \(key)")
    }

    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("[Cache] Cleared all cache")
    }

    // MARK: - Cache Size Management

    private func enforceCacheSizeLimit() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else {
            return
        }

        // Calculate total size
        var totalSize = 0
        for file in files where file.pathExtension == "json" {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += size
            }
        }

        // If over limit, remove oldest files
        if totalSize > maxCacheSize {
            print("[Cache] Cache size (\(totalSize) bytes) exceeds limit (\(maxCacheSize) bytes), cleaning up...")

            // Sort files by creation date (oldest first)
            let sortedFiles = files.filter { $0.pathExtension == "json" }.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 < date2
            }

            // Remove files until under limit
            var currentSize = totalSize
            for file in sortedFiles {
                guard currentSize > maxCacheSize * 3 / 4 else { break } // Remove until 75% of limit

                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    try? FileManager.default.removeItem(at: file)

                    // Also remove metadata file
                    let metadataURL = file.deletingPathExtension().appendingPathExtension("meta")
                    try? FileManager.default.removeItem(at: metadataURL)

                    currentSize -= size
                    print("[Cache] Removed old cache file: \(file.lastPathComponent)")
                }
            }
        }
    }

    private func cleanupOldCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: []) else {
            return
        }

        var removedCount = 0
        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            if isExpired(forKey: key) {
                clearCache(forKey: key)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            print("[Cache] Cleaned up \(removedCount) expired cache files")
        }
    }

    // MARK: - Private Helpers

    private func cacheFileURL(for key: String) -> URL {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(safeKey).json")
    }

    private func metadataFileURL(for key: String) -> URL {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(safeKey).meta")
    }

    private func saveMetadata(forKey key: String, data: Data, expiresIn: TimeInterval) {
        let metadataURL = metadataFileURL(for: key)
        let metadata: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "size": data.count,
            "expiration": expiresIn
        ]

        if let plistData = try? PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0) {
            try? plistData.write(to: metadataURL)
        }
    }

    private func loadMetadata(forKey key: String) -> [String: Any]? {
        let metadataURL = metadataFileURL(for: key)
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    // MARK: - Cache Statistics

    func getCacheStats() -> (count: Int, size: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (0, "0 B")
        }

        var totalSize = 0
        var jsonFiles = 0

        for file in files {
            if file.pathExtension == "json" {
                jsonFiles += 1
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += size
                }
            }
        }

        let sizeString: String
        if totalSize > 1024 * 1024 {
            sizeString = String(format: "%.1f MB", Double(totalSize) / 1024 / 1024)
        } else if totalSize > 1024 {
            sizeString = String(format: "%.1f KB", Double(totalSize) / 1024)
        } else {
            sizeString = "\(totalSize) B"
        }

        return (jsonFiles, sizeString)
    }
}

// MARK: - Cache Keys

extension CacheManager {
    struct CacheKeys {
        static func forumList() -> String { return "forum_list" }
        static func threadList(fid: Int, page: Int) -> String { return "thread_list_fid\(fid)_page\(page)" }
        static func threadDetail(tid: Int, page: Int) -> String { return "thread_detail_tid\(tid)_page\(page)" }
        static func searchResults(keyword: String, page: Int) -> String {
            let safeKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? keyword
            return "search_\(safeKeyword)_page\(page)"
        }
        static func privateMessages(page: Int) -> String { return "pm_list_page\(page)" }
    }
}
