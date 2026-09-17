import Foundation

/// Пользователь, баланс минут и вход/выход.
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var isLoggedIn: Bool
    @Published private(set) var user: User?
    @Published private(set) var balance: Balance?

    private var expiredObserver: NSObjectProtocol?

    init() {
        // Keychain переживает удаление приложения: после переустановки начинаем без старого токена.
        if !UserDefaults.standard.bool(forKey: "installed") {
            TokenStore.clear()
            UserDefaults.standard.set(true, forKey: "installed")
        }
        isLoggedIn = TokenStore.access != nil
        expiredObserver = NotificationCenter.default.addObserver(forName: APIClient.sessionExpired, object: nil, queue: .main) { [weak self] _ in
            // Записи не трогаем: после повторного входа того же пользователя они доотправятся.
            Task { @MainActor in self?.signedOut() }
        }
    }

    func login(email: String, password: String) async throws {
        struct Input: Encodable { let email: String; let password: String }
        let pair: TokenPair = try await APIClient.shared.send("POST", "auth/login",
            body: .json(Input(email: AuthForm.normalize(email), password: password)), auth: false)
        signedIn(pair)
    }

    func register(name: String, email: String, password: String) async throws {
        struct Input: Encodable { let email: String; let password: String; let full_name: String }
        let pair: TokenPair = try await APIClient.shared.send("POST", "auth/register",
            body: .json(Input(email: AuthForm.normalize(email), password: password, full_name: name.trimmingCharacters(in: .whitespaces))), auth: false)
        signedIn(pair)
    }

    func refresh() async {
        guard isLoggedIn else { return }
        if let me: User = try? await APIClient.shared.send("GET", "auth/me") { user = me }
        if let b: Balance = try? await APIClient.shared.send("GET", "billing/balance") { balance = b }
    }

    /// Выход по кнопке: неотправленные записи удаляются, под чужим токеном их слать нельзя.
    func logout() {
        TokenStore.clear()
        Uploader.shared.discardAll()
        signedOut()
    }

    private func signedIn(_ pair: TokenPair) {
        TokenStore.save(pair)
        let lastUserId = UserDefaults.standard.string(forKey: "userId")
        if let id = pair.user?.id, lastUserId != nil, lastUserId != id {
            // ponytail: записи прошлого аккаунта удаляются молча; если начнут жаловаться, спрашивать перед входом.
            Uploader.shared.discardAll()
        }
        UserDefaults.standard.set(pair.user?.id, forKey: "userId")
        user = pair.user
        isLoggedIn = true
        Uploader.shared.kick()
        Task { await refresh() }
    }

    private func signedOut() {
        user = nil
        balance = nil
        isLoggedIn = false
    }
}

/// Проверки формы входа и регистрации, тексты как в Android.
enum AuthForm {
    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func loginError(email: String, password: String, agreed: Bool) -> String? {
        if normalize(email).isEmpty || password.isEmpty { return "Введите e-mail и пароль" }
        if !agreed { return "Необходимо принять политику конфиденциальности" }
        return nil
    }

    static func registerError(name: String, email: String, password: String, repeat again: String, agreed: Bool) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty || normalize(email).isEmpty || password.isEmpty { return "Заполните все поля" }
        if !normalize(email).contains("@") { return "Проверьте e-mail" }
        if password.count < 6 { return "Пароль должен быть не короче 6 символов" }
        if password != again { return "Пароли не совпадают" }
        if !agreed { return "Необходимо принять политику конфиденциальности" }
        return nil
    }
}
