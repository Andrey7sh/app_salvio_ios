import SwiftUI

/// Вход и регистрация только по e-mail (PIVOT_PLAN.md §6).
struct AuthView: View {
    @EnvironmentObject private var session: AppSession
    @State private var isRegister = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var again = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if isRegister {
                    Section {
                        TextField("Имя", text: $name).textContentType(.name)
                    }
                }
                Section {
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(isRegister ? "Пароль, минимум 6 символов" : "Пароль", text: $password)
                        .textContentType(isRegister ? .newPassword : .password)
                    if isRegister {
                        SecureField("Повторите пароль", text: $again).textContentType(.newPassword)
                    }
                } footer: {
                    if isRegister {
                        Text("Подтвердите почту после регистрации и получите 30 бесплатных минут записи")
                    }
                }
                Section {
                    Toggle(isOn: $agreed) {
                        Text("Я принимаю [пользовательское соглашение и политику конфиденциальности](https://salvio.io/mob_terms)")
                            .font(.footnote)
                    }
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text(isRegister ? "Зарегистрироваться" : "Войти").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy)
                } footer: {
                    if let error { Text(error).foregroundColor(.red) }
                }
                Section {
                    Button(isRegister ? "У меня уже есть аккаунт" : "Нет аккаунта? Зарегистрироваться") {
                        isRegister.toggle()
                        error = nil
                    }
                }
            }
            .navigationTitle(isRegister ? "Регистрация" : "Вход")
        }
    }

    private func submit() {
        error = isRegister
            ? AuthForm.registerError(name: name, email: email, password: password, repeat: again, agreed: agreed)
            : AuthForm.loginError(email: email, password: password, agreed: agreed)
        guard error == nil else { return }
        busy = true
        Task {
            do {
                if isRegister {
                    try await session.register(name: name, email: email, password: password)
                } else {
                    try await session.login(email: email, password: password)
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
