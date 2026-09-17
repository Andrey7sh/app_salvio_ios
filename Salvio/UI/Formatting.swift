import Foundation

enum Format {
    /// 65 → «01:05», 3725 → «1:02:05».
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func date(_ iso: String?) -> String {
        guard let date = ISO8601DateFormatter.parseFlexible(iso) else { return "" }
        return date.formatted(.dateTime.locale(Locale(identifier: "ru_RU")).day().month(.wide).hour().minute())
    }

    /// Статусы звонка на сервере, тексты как в Android 1.3.
    static func status(_ status: String?) -> String {
        switch status {
        case "pending_upload": return "Ожидает отправки"
        case "uploading": return "Выгружается..."
        case "uploaded", "transcribing", "transcribed": return "Отправлено, ждёт обработки"
        case "analyzing": return "Обрабатывается..."
        case "done": return "Готово"
        case "error": return "Ошибка"
        case "awaiting_payment": return "Ждёт оплаты"
        default: return status ?? ""
        }
    }

    static func isProcessing(_ status: String?) -> Bool {
        !["done", "error", "awaiting_payment"].contains(status ?? "")
    }

    /// Текст для «Поделиться»: заголовок и секции сценария.
    static func shareText(title: String, sections: [ResultSection]) -> String {
        let body = sections.filter { !$0.text.isEmpty }.map { "\($0.title ?? ""):\n\($0.text)" }
        return ([title] + body).joined(separator: "\n\n")
    }
}
