import Foundation

/// Журнал приложения: почему запись встала на паузу, что ответил сервер на чанк, когда ушёл finish.
/// Пишется в файл, виден в «Профиль → Диагностика», оттуда же отправляется в поддержку.
/// Персональных данных не пишем: ни текстов встреч, ни токенов, ни e-mail.
final class RecordingLog {
    static let shared = RecordingLog()
    static let maxBytes = 512 * 1024

    private let queue = DispatchQueue(label: "io.salvio.log")
    private let url: URL
    private let previousURL: URL
    private let stamp: DateFormatter

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("salvio.log")
        previousURL = base.appendingPathComponent("salvio-previous.log")
        stamp = DateFormatter()
        stamp.dateFormat = "dd.MM HH:mm:ss"
    }

    func callAsFunction(_ tag: String, _ message: String) {
        write("\(stamp.string(from: Date())) [\(tag)] \(message)")
    }

    private func write(_ line: String) {
        queue.async {
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: self.url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: self.url)
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: self.url.path)
            let size = (attributes?[.size] as? Int) ?? 0
            if size > Self.maxBytes {
                try? FileManager.default.removeItem(at: self.previousURL)
                try? FileManager.default.moveItem(at: self.url, to: self.previousURL)
            }
        }
    }

    /// Последние строки для экрана диагностики, новые сверху.
    func tail(_ lines: Int = 300) -> [String] {
        queue.sync {}
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let previous = (try? String(contentsOf: previousURL, encoding: .utf8)) ?? ""
        return (previous + current)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(lines)
            .map(String.init)
            .reversed()
    }

    /// Файл для кнопки «Отправить в поддержку».
    func exportFile() -> URL? {
        queue.sync {}
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("salvio-log.txt")
        let text = ((try? String(contentsOf: previousURL, encoding: .utf8)) ?? "") + ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        guard !text.isEmpty else { return nil }
        do {
            try Data(text.utf8).write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: self.url)
            try? FileManager.default.removeItem(at: self.previousURL)
        }
    }
}

/// Короткая запись в журнал: appLog("rec", "старт"). Имя не log, чтобы не перекрыть log() из Foundation.
let appLog = RecordingLog.shared
