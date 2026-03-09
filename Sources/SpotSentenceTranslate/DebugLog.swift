import Foundation

enum DebugLog {
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

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
