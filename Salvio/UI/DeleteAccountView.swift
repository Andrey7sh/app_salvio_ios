import SwiftUI

/// Удаление аккаунта с подтверждением паролем (App Store 5.1.1(v)).
struct DeleteAccountView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Удаляются аккаунт, все встречи, аудиозаписи, транскрипты и итоги. Ссылки, которыми вы делились, перестанут открываться. Восстановить данные будет нельзя.")
                }
                Section {
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Подтвердите паролем")
                } footer: {
                    if let error { Text(error).foregroundColor(.red) }
                }
                Section {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Удалить аккаунт").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || password.isEmpty)
                }
            }
            .navigationTitle("Удаление аккаунта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(busy)
                }
            }
        }
    }

    private func delete() {
        busy = true
        error = nil
        Task {
            do {
                try await session.deleteAccount(password: password)
                dismiss()
            } catch {
                self.error = (error as? APIError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }
}
