import Foundation

enum DebugLog {
    // 统一写到 /tmp，便于现场排查时直接 tail 查看。
    private static let logURL = URL(fileURLWithPath: "/tmp/SpotSentenceTranslate.log")

    static func reset() {
        try? FileManager.default.removeItem(at: logURL)
    }

    static func write(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: logURL.path) == false {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            return
        }

        // 用追加写入保持日志时序，避免并发覆盖旧内容。
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
