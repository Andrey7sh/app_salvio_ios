import Foundation

// Паритет с веб-кабинетом (Мобильное приложение/План_паритет_с_вебом.md), те же запросы, что в Android 1.4.6:
// транскрипт частями, спикеры, чат, папки, корзина, вкладки итогов, ссылка, экспорт, шаблоны, настройки.

struct TranscriptPage: Decodable {
    let segments: [TranscriptSegment]
    /// Сколько реплик всего. nil у старого бэкенда и у ответа 202 «ещё обрабатывается».
    let total: Int?
    let speakerNames: [String: String]
    let speakerRoles: [String: String]

    enum CodingKeys: String, CodingKey {
        case segments, total
        case speakerNames = "speaker_names", speakerRoles = "speaker_roles"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = try c.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        speakerNames = try c.decodeIfPresent([String: String].self, forKey: .speakerNames) ?? [:]
        speakerRoles = try c.decodeIfPresent([String: String].self, forKey: .speakerRoles) ?? [:]
    }
}

struct TranscriptSegment: Decodable, Hashable {
    let startMs: Int?
    let endMs: Int?
    let speaker: String?
    let speakerLabel: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms", endMs = "end_ms", speaker, speakerLabel = "speaker_label", text
    }
}

struct FoldersResponse: Decodable {
    let all: Int?
    let unfiled: Int?
    let trash: Int?
    let folders: [Folder]
}

struct Folder: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int?
}

struct ChatResponse: Decodable { let messages: [ChatMessage] }

struct ChatMessage: Decodable, Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
}

struct SummariesResponse: Decodable { let summaries: [SummaryTab] }

struct SummaryTab: Decodable, Identifiable {
    let id: String
    let kind: String?
    let title: String?
    let status: String?
    let isPrimary: Bool?
    let sections: [ResultSection]?
    let error: String?

    var pending: Bool { status == "queued" || status == "processing" }
}

struct ScenarioCard: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let icon: String?
    let description: String?

    var label: String { [icon, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
}

struct ScenariosResponse: Decodable { let scenarios: [ScenarioCard] }
struct DefaultScenarioResponse: Decodable { let defaultScenario: Scenario? }

/// /me/preferences. PUT частичный: nil-поля не кодируются и не затирают настройки на сервере.
struct Preferences: Codable, Equatable {
    var aiPreferences: AIPreferences?
    var vocabulary: Vocabulary?
    var transcriptionLanguage: String?
    var speakerRoles: [SpeakerRole]?
    var options: Options?

    enum CodingKeys: String, CodingKey {
        case aiPreferences = "ai_preferences", vocabulary, transcriptionLanguage = "transcription_language"
        case speakerRoles = "speaker_roles", options
    }

    struct AIPreferences: Codable, Equatable {
        var about: String = ""
        var focus: [String] = []
        var style: [String] = []
    }

    struct Vocabulary: Codable, Equatable {
        var enabled: Bool = true
        var industry: String?
        var terms: [String] = []
    }

    struct SpeakerRole: Codable, Equatable, Identifiable, Hashable {
        var id: String = ""
        var title: String
        var fullName: String = ""

        enum CodingKeys: String, CodingKey { case id, title, fullName = "full_name" }

        init(id: String = "", title: String, fullName: String = "") {
            self.id = id; self.title = title; self.fullName = fullName
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
            title = try c.decode(String.self, forKey: .title)
            fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        }
    }

    struct Options: Codable, Equatable {
        var focus: [String] = []
        var style: [String] = []
        var languages: [String: String] = [:]
        var industries: [String: String] = [:]
    }

    /// Лимиты сервера (salvio-web services/preferences.py): больше он отклонит с 422.
    static let maxTerms = 500
    static let maxRoles = 20
}

/// Разделы публичной ссылки и форматы файлов, как в веб-кабинете.
enum ShareSection: String, CaseIterable, Identifiable {
    case summary, transcript, checklist, audio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return "Итоги"
        case .transcript: return "Транскрипт"
        case .checklist: return "Чек-лист"
        case .audio: return "Аудиозапись"
        }
    }
}

enum MeetingAPI {
    /// ~5-8 КБ после gzip на страницу: укладывается в окно до заморозки под VPN.
    static let transcriptPage = 100
    private static var api: APIClient { .shared }

    static func transcript(_ id: String, offset: Int) async throws -> TranscriptPage {
        try await api.send("GET", "calls/\(id)/transcript?offset=\(offset)&limit=\(transcriptPage)&text=false",
                           decoder: .plain, oneShot: true)
    }

    static func saveSpeakers(_ id: String, names: [String: String], roles: [String: String]) async throws {
        struct Input: Encodable { let names: [String: String]; let roles: [String: String] }
        _ = try await api.raw("PUT", "calls/\(id)/speakers", body: .json(Input(names: names, roles: roles)))
    }

    static func restart(_ id: String, retranscribe: Bool) async throws -> String? {
        struct Input: Encodable { let retranscribe: Bool }
        let r: StatusResponse = try await api.send("POST", "calls/\(id)/restart-analysis", body: .json(Input(retranscribe: retranscribe)))
        return r.status
    }

    static func trash(_ id: String) async throws { _ = try await api.raw("DELETE", "calls/\(id)") }
    static func restore(_ id: String) async throws { _ = try await api.raw("POST", "calls/\(id)/restore") }
    static func purge(_ id: String) async throws { _ = try await api.raw("DELETE", "calls/\(id)/purge") }

    /// folderId nil: «Без папки». move=true обязателен, иначе сервер не тронет папку.
    static func move(_ id: String, to folderId: String?) async throws {
        struct Input: Encodable {
            let folderId: String?
            let move = true
            enum CodingKeys: String, CodingKey { case folderId = "folder_id", move }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(folderId, forKey: .folderId)  // явный null: вынести из папки
                try c.encode(move, forKey: .move)
            }
        }
        _ = try await api.raw("PATCH", "calls/\(id)", body: .json(Input(folderId: folderId)))
    }

    static func search(q: String?, folder: String?, page: Int) async throws -> CallsPage {
        var items = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "limit", value: "20")]
        if let q, !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if let folder { items.append(URLQueryItem(name: "folder", value: folder)) }
        var c = URLComponents(); c.queryItems = items
        return try await api.send("GET", "calls?\(c.percentEncodedQuery ?? "")")
    }

    static func folders() async throws -> FoldersResponse { try await api.send("GET", "folders") }

    struct NameInput: Encodable { let name: String }
    static func createFolder(_ name: String) async throws -> Folder {
        try await api.send("POST", "folders", body: .json(NameInput(name: name)))
    }
    static func renameFolder(_ id: String, _ name: String) async throws -> Folder {
        try await api.send("PATCH", "folders/\(id)", body: .json(NameInput(name: name)))
    }
    static func deleteFolder(_ id: String) async throws { _ = try await api.raw("DELETE", "folders/\(id)") }

    static func chat(_ id: String) async throws -> [ChatMessage] {
        let r: ChatResponse = try await api.send("GET", "calls/\(id)/chat")
        return r.messages
    }

    /// Ответ генерируется в том же запросе, до минуты: таймаут длиннее обычного.
    static func ask(_ id: String, _ question: String) async throws -> ChatMessage {
        struct Input: Encodable { let question: String }
        return try await api.send("POST", "calls/\(id)/chat", body: .json(Input(question: question)), timeout: 120)
    }

    static func saveAnswer(_ id: String, messageId: String) async throws {
        struct Input: Encodable { let title = "" }
        _ = try await api.raw("POST", "calls/\(id)/chat/\(messageId)/save", body: .json(Input()))
    }

    static func summaries(_ id: String) async throws -> [SummaryTab] {
        let r: SummariesResponse = try await api.send("GET", "calls/\(id)/summaries")
        return r.summaries
    }

    static func addSummary(_ id: String, scenarioId: String) async throws -> SummaryTab {
        struct Input: Encodable { let scenario_id: String }
        return try await api.send("POST", "calls/\(id)/summaries", body: .json(Input(scenario_id: scenarioId)))
    }

    static func makePrimary(_ id: String, summaryId: String) async throws {
        struct Input: Encodable { let is_primary = true }
        _ = try await api.raw("PATCH", "calls/\(id)/summaries/\(summaryId)", body: .json(Input()))
    }

    static func share(_ id: String) async throws -> ShareLinkInfo? {
        let r: ShareLookup = try await api.send("GET", "calls/\(id)/share")
        return r.share
    }

    static func createShare(_ id: String, sections: [String]) async throws -> ShareLinkInfo {
        struct Input: Encodable { let sections: [String] }
        return try await api.send("POST", "calls/\(id)/share", body: .json(Input(sections: sections)))
    }

    static func revokeShare(_ id: String) async throws { _ = try await api.raw("DELETE", "calls/\(id)/share") }

    /// Файл с заголовком Bearer: ссылкой не поделиться, скачиваем во временную папку и отдаём в «Поделиться».
    static func export(_ id: String, what: String, fmt: String, title: String, summaryId: String?) async throws -> URL {
        var path = "calls/\(id)/export?what=\(what)&fmt=\(fmt)"
        if what == "summary", let summaryId { path += "&summary_id=\(summaryId)" }
        let data = try await api.raw("GET", path, timeout: 120)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(Format.fileName(title)) - \(what == "transcript" ? "транскрипт" : "итоги").\(fmt)")
        try data.write(to: url)
        return url
    }

    static func popularScenarios() async throws -> [ScenarioCard] {
        let r: ScenariosResponse = try await api.send("GET", "scenarios/popular")
        return r.scenarios
    }

    static func scenarios() async throws -> [ScenarioCard] {
        let r: ScenariosResponse = try await api.send("GET", "scenarios")
        return r.scenarios
    }

    static func setDefaultScenario(_ scenarioId: String) async throws -> Scenario? {
        struct Input: Encodable { let scenario_id: String }
        let r: DefaultScenarioResponse = try await api.send("PUT", "scenarios/default", body: .json(Input(scenario_id: scenarioId)))
        return r.defaultScenario
    }

    static func preferences() async throws -> Preferences { try await api.send("GET", "me/preferences", decoder: .plain) }

    static func savePreferences(_ patch: Preferences) async throws -> Preferences {
        try await api.send("PUT", "me/preferences", body: .json(patch), decoder: .plain)
    }
}
