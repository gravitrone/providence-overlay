import Foundation

enum Logger {
    private static let q = DispatchQueue(label: "overlay.logger")
    private static let path: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".providence/log", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("overlay.log")
    }()

    static func log(_ msg: @autoclosure () -> String) {
        let text = msg()
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        q.async {
            if FileManager.default.fileExists(atPath: path.path) {
                if let h = try? FileHandle(forWritingTo: path) {
                    _ = try? h.seekToEnd()
                    try? h.write(contentsOf: Data(line.utf8))
                    try? h.close()
                }
            } else {
                try? Data(line.utf8).write(to: path)
            }
        }
        FileHandle.standardError.write(Data(line.utf8))
    }
}
