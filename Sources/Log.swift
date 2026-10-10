// Log.swift – prosty dziennik zdarzeń w ~/Library/Logs/iWorkBar.log
// Pozwala sprawdzić, co dokładnie dzieje się po dotknięciu przycisku.

import Foundation

enum Log {
    static let fileURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("iWorkBar.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        NSLog("iWorkBar: %@", message)
        guard let data = line.data(using: .utf8) else { return }

        // Plik ograniczony do ok. 500 KB – starszy zapis jest zastępowany.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int, size > 500_000 {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
