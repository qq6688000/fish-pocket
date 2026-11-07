import Foundation

/// 运行日志：把 App 侧发生的事按时间记下来（选文件、上传、导入、错误），
/// 和引擎日志一起在 设置 → 运行日志 里导出。只保留最近若干条，重启即清空。
enum RunLog {
    private static let lock = NSLock()
    private static var entries: [(Date, String)] = []
    private static let limit = 400

    static func note(_ text: String) {
        let stamp = Date()
        lock.lock()
        entries.append((stamp, text))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        lock.unlock()
    }

    static func note(_ text: String, error: Error) {
        note("\(text)：\(error.localizedDescription)")
    }

    static var text: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return snapshot.map { "\(formatter.string(from: $0.0))  \($0.1)" }.joined(separator: "\n")
    }

    static var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.isEmpty
    }
}

/// 外部选择器给的 security-scoped URL：先整份拷进沙盒，之后随便读，
/// 不再依赖作用域还在不在。iCloud 的占位文件由 NSFileCoordinator 负责下载。
enum PickedFile {
    enum Failure: LocalizedError {
        case staged
        var errorDescription: String? { "读取文件失败（无法访问所选文件）" }
    }

    @discardableResult
    static func stage(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("picked/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)

        var coordinatorError: NSError?
        var copyError: Error?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: destination)
                copied = true
            } catch {
                copyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let copyError { throw copyError }
        guard copied else { throw Failure.staged }
        return destination
    }

    /// UTF-8 first, then the encodings a file from a Windows machine usually carries.
    static func text(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1] {
            if let text = String(data: data, encoding: encoding), !text.isEmpty { return text }
        }
        return nil
    }
}
