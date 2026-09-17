import Foundation

// Модели ответов backend app.salvio.io. Ключи snake_case переводит JSONDecoder.api,
// поля опциональны: backend отдаёт null и расширяет ответы без версии API.

struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: User?
}

struct User: Decodable, Equatable {
    let id: String
    let email: String
    let fullName: String?
    let emailVerified: Bool?
    // Профиль работы (PIVOT_PLAN.md §3): сценарий выбирается в веб-кабинете.
    let defaultScenario: Scenario?
}

struct Scenario: Decodable, Equatable {
    let id: String?
    let key: String?
    let name: String?
    let icon: String?
    let outputSchema: [SectionSchema]?
    let hasChecklist: Bool?

    var label: String? {
        guard let name, !name.isEmpty else { return nil }
        return [icon, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct SectionSchema: Decodable, Equatable {
    let key: String?
    let title: String?
}

struct Balance: Decodable, Equatable {
    let balanceMinutes: Int
    let lowBalance: Bool
}

struct CallsPage: Decodable {
    let items: [CallItem]
    let page: Int
    let totalPages: Int
}

struct CallItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let startedAt: String?
    let durationSeconds: Int?
    let status: String?
}

struct CallDetail: Decodable {
    let id: String
    let title: String?
    let status: String?
    let startedAt: String?
    let durationSeconds: Int?
    let audioUrl: String?
}

struct CallResult: Decodable {
    let scenario: Scenario?
    let sections: [ResultSection]
    let ready: Bool
    let status: String?
}

struct ResultSection: Decodable {
    let key: String?
    let title: String?
    let value: JSONValue?

    var text: String { value?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

struct ChecklistResponse: Decodable {
    let checklist: Checklist?
}

struct Checklist: Decodable {
    let checklistName: String?
    let scoreAverage: Double?
    let categories: [ChecklistCategory]
}

struct ChecklistCategory: Decodable {
    let name: String?
    let items: [ChecklistItem]
}

struct ChecklistItem: Decodable {
    let criterion: String?
    let value: JSONValue?
    let comment: String?

    // Как в Android: yes/да, partial/частично, остальное считается «нет».
    var verdict: String {
        let v = (value?.plainText ?? "").lowercased()
        if v.contains("yes") || v.contains("да") { return "Да" }
        if v.contains("partial") || v.contains("частично") { return "Частично" }
        return "Нет"
    }
}

struct Transcript: Decodable {
    let segments: [TranscriptSegment]
    let transcriptText: String?
}

struct TranscriptSegment: Decodable {
    let startMs: Int?
    let speakerLabel: String?
    let text: String?
}

struct ShareLinkInfo: Decodable {
    let url: String?
    let token: String?
}

struct ShareLookup: Decodable {
    let share: ShareLinkInfo?
}

struct StartCallResponse: Decodable {
    let id: String
}

struct StatusResponse: Decodable {
    let status: String?
}

/// Значение секции сценария: строка, число, список или объект.
enum JSONValue: Decodable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    /// Текст для экрана и «Поделиться», формат как у Android asPlainText.
    var plainText: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return a.map { "• " + $0.plainText }.joined(separator: "\n")
        case .object(let o): return o.keys.sorted().map { "\($0): \(o[$0]!.plainText)" }.joined(separator: "\n")
        case .null: return ""
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

/// Ошибка API: {"detail": {"error", "message", "details"}}, {"detail": "..."} или pydantic-список.
struct APIError: Error, LocalizedError, Equatable {
    let status: Int
    let code: String?
    let message: String
    let details: JSONValue?

    var errorDescription: String? { message }

    static let offline = APIError(status: 0, code: "offline", message: "Нет интернет-соединения", details: nil)

    static func parse(status: Int, data: Data) -> APIError {
        if status >= 500 {
            return APIError(status: status, code: nil, message: "Сервер временно недоступен", details: nil)
        }
        let body = try? JSONDecoder().decode(JSONValue.self, from: data)
        let detail = body?["detail"]
        switch detail {
        case .object(_)?:
            return APIError(status: status, code: detail?["error"]?.plainText,
                            message: detail?["message"]?.plainText ?? "Ошибка сервера: \(status)",
                            details: detail?["details"])
        case .string(let s)?:
            return APIError(status: status, code: nil, message: s, details: nil)
        case .array(let list)?:
            return APIError(status: status, code: "validation", message: list.first?["msg"]?.plainText ?? "Проверьте данные", details: nil)
        default:
            return APIError(status: status, code: nil, message: "Ошибка сервера: \(status)", details: nil)
        }
    }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
