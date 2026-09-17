import Foundation

enum RequestBody {
    case json(Encodable)
    case form([(String, String)])
}

/// HTTP-клиент к https://app.salvio.io/api/. Bearer из Keychain, при 401 один refresh и повтор.
final class APIClient {
    static let shared = APIClient()
    static let baseURL = URL(string: "https://app.salvio.io/api/")!
    /// Refresh-токен отклонён: Session разлогинивает пользователя.
    static let sessionExpired = Notification.Name("SalvioSessionExpired")

    private let session: URLSession
    private let refresher = SingleFlight()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<T: Decodable>(_ method: String = "GET", _ path: String, body: RequestBody? = nil, auth: Bool = true) async throws -> T {
        let data = try await raw(method, path, body: body, auth: auth)
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            throw APIError(status: 200, code: "decode", message: "Не удалось прочитать ответ сервера", details: nil)
        }
    }

    func raw(_ method: String, _ path: String, body: RequestBody? = nil, auth: Bool = true) async throws -> Data {
        var (data, status) = try await perform(method, path, body: body, auth: auth)
        if status == 401, auth, TokenStore.refresh != nil {
            try await refreshTokens()
            (data, status) = try await perform(method, path, body: body, auth: auth)
        }
        guard (200..<300).contains(status) else { throw APIError.parse(status: status, data: data) }
        return data
    }

    /// Параллельные 401 (экран и фоновые загрузки) делают один refresh на всех.
    func refreshTokens() async throws {
        try await refresher.run { [self] in
            guard let refresh = TokenStore.refresh else { throw APIError(status: 401, code: "no_refresh", message: "Войдите заново", details: nil) }
            struct Input: Encodable { let refresh_token: String }
            let (data, status) = try await perform("POST", "auth/refresh", body: .json(Input(refresh_token: refresh)), auth: false)
            guard status == 200, let pair = try? JSONDecoder.api.decode(TokenPair.self, from: data) else {
                let error = APIError.parse(status: status, data: data)
                if status == 401 || status == 403 {
                    TokenStore.clear()
                    await MainActor.run { NotificationCenter.default.post(name: APIClient.sessionExpired, object: nil) }
                }
                throw error
            }
            TokenStore.save(pair)
        }
    }

    static func makeRequest(_ method: String, _ path: String, body: RequestBody?, token: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        switch body {
        case .json(let value)?:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(value)
        case .form(let fields)?:
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncode(fields).utf8)
        case nil:
            break
        }
        return request
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        // Только ASCII: .alphanumerics пропустил бы кириллицу без кодирования.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return fields.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
    }

    private func perform(_ method: String, _ path: String, body: RequestBody?, auth: Bool) async throws -> (Data, Int) {
        let request = Self.makeRequest(method, path, body: body, token: auth ? TokenStore.access : nil)
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw APIError.offline
        }
    }
}

actor SingleFlight {
    private var current: Task<Void, Error>?

    func run(_ operation: @escaping () async throws -> Void) async throws {
        if let current { return try await current.value }
        let task = Task { try await operation() }
        current = task
        defer { current = nil }
        try await task.value
    }
}

extension ISO8601DateFormatter {
    /// Backend отдаёт isoformat() с дробными секундами или без них.
    static func parseFlexible(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: string) { return d }
        // Python isoformat() даёт микросекунды, их парсер понимает не на всех версиях iOS.
        let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return f.date(from: trimmed)
    }
}
