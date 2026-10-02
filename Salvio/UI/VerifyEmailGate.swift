import SwiftUI
import UIKit

/// Экран вместо записи, пока почта не подтверждена: без подтверждения на балансе 0 минут, а строку
/// в карточке люди не замечали и уходили через полминуты после регистрации (разбор 02.10.2026).
/// Подтверждение подхватывается само: при возврате в приложение RootView обновляет профиль.
struct VerifyEmailGate: View {
    @EnvironmentObject private var session: AppSession
    let onLater: () -> Void
    @State private var sent = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "envelope.badge")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            Text("Подтвердите почту").font(.title2).bold()
            Text("Мы отправили письмо на \(session.user?.email ?? "вашу почту"). Нажмите ссылку в письме, и на балансе появятся 30 бесплатных минут.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button {
                Analytics.track("verify_open_mail")
                openMail(session.user?.email)
            } label: {
                Text("Открыть почту").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                check()
            } label: {
                Text("Я подтвердил почту").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(busy)
            if sent {
                Text("Письмо отправлено ещё раз. Если его нет во «Входящих», проверьте «Спам»")
                    .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
            } else {
                Button("Письмо не пришло? Отправить ещё раз") { resend() }.disabled(busy)
            }
            if let message {
                Text(message).font(.footnote).foregroundColor(.orange).multilineTextAlignment(.center)
            }
            Spacer()
            Button("Подтвержу позже") {
                Analytics.track("verify_later")
                onLater()
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .onAppear { Analytics.track("verify_screen_shown") }
    }

    private func check() {
        busy = true
        Task {
            await session.refresh()
            if session.user?.emailVerified == false {
                message = "Почта ещё не подтверждена. Откройте ссылку из письма"
            } else {
                Analytics.track("verify_email_done")
            }
            busy = false
        }
    }

    private func resend() {
        busy = true
        Task {
            do { try await session.resendVerifyEmail(); sent = true; message = nil }
            catch { message = "Не удалось отправить письмо, попробуйте позже" }
            busy = false
        }
    }

    /// Ящики mail.ru, Яндекса и Gmail открываем веб-почтой (приложение ящика, если стоит, перехватит ссылку само),
    /// остальные в стандартной «Почте».
    /// ponytail: три известных домена; расширять картой по статистике регистраций.
    private func openMail(_ email: String?) {
        let domain = email?.split(separator: "@").last.map { $0.lowercased() } ?? ""
        let link: String
        switch domain {
        case "mail.ru", "inbox.ru", "list.ru", "bk.ru", "internet.ru": link = "https://e.mail.ru/inbox/"
        case "yandex.ru", "ya.ru", "yandex.com", "yandex.by", "yandex.kz": link = "https://mail.yandex.ru/"
        case "gmail.com", "googlemail.com": link = "https://mail.google.com/"
        default: link = "message://"
        }
        guard let url = URL(string: link) else { return }
        UIApplication.shared.open(url) { ok in
            if !ok { message = "Откройте почту вручную: письмо от no-reply@salvio.io" }
        }
    }
}
