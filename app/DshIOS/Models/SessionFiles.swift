import Foundation

/// 删除一个会话在磁盘上的记录。引擎没有 `session/delete`，只能归档之后自己清文件；
/// `$DSH_HOME` 是引擎自己的路径，经 `EnginePaths` 换成本机的真实路径。
enum SessionFiles {
    /// Delete every entry named after the session id. Returns how many were removed.
    @discardableResult
    static func delete(_ sessionId: String) -> Int {
        let home = EnginePaths.dshHome
        guard FileManager.default.fileExists(atPath: home.path) else { return 0 }
        guard let walk = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }

        // Collect first: removing while enumerating invalidates the enumerator.
        var victims: [URL] = []
        for case let url as URL in walk {
            let name = url.lastPathComponent
            if name == sessionId || name.hasPrefix(sessionId + ".") || name.hasSuffix("-" + sessionId) {
                victims.append(url)
            }
        }
        var removed = 0
        for url in victims.sorted(by: { $0.path.count > $1.path.count }) {
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
