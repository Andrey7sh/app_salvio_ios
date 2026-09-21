import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared
    @ObservedObject private var uploader = Uploader.shared
    @State private var confirmLogout = false
    @State private var consentGranted = RecordingConsent.granted
    @State private var deleting = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    /// Письмо в поддержку с уже заполненными данными: аккаунт, версия, модель и iOS.
    /// Иначе в обращении не хватает контекста и приходится переспрашивать.
    private var supportMailURL: URL {
        let body = """


        ---
        Данные для поддержки, не удаляйте:
        Аккаунт: \(session.user?.email ?? "не определён")
        Версия приложения: \(version)
        Устройство: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@salvio.io"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Salvio iOS \(version): обращение в поддержку"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:support@salvio.io")!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Аккаунт") {
                    LabeledContent("Имя", value: session.user?.fullName ?? "")
                    LabeledContent("E-mail", value: session.user?.email ?? "")
                    if session.user?.emailVerified == false {
                        Text("Подтвердите почту по письму, чтобы получить 30 бесплатных минут").foregroundColor(.orange)
                    }
                }
                Section {
                    LabeledContent("Профиль работы", value: session.user?.defaultScenario?.label ?? "не выбран")
                    LabeledContent("На балансе", value: session.balance.map { "\($0.balanceMinutes) мин" } ?? "…")
                } footer: {
                    Text("Профиль работы настраивается в веб-кабинете")
                }
                Section {
                    Toggle("Согласие на запись и обработку", isOn: Binding(
                        get: { consentGranted },
                        set: { value in
                            RecordingConsent.granted = value
                            consentGranted = value
                        }
                    ))
                    .disabled(recorder.isRecording)
                } footer: {
                    Text("Без согласия новые записи не создаются. Уже загруженные встречи остаются в аккаунте, их можно удалить в веб-кабинете.")
                }
                Section {
                    Link("Пользовательское соглашение", destination: URL(string: "https://salvio.io/mob_terms")!)
                    Link("Написать в поддержку", destination: supportMailURL)
                    NavigationLink("Диагностика") { DiagnosticsView() }
                    LabeledContent("Версия приложения", value: version)
                }
                Section {
                    Button("Выйти", role: .destructive) { confirmLogout = true }
                        .disabled(recorder.isRecording)
                } footer: {
                    if recorder.isRecording { Text("Остановите запись перед выходом") }
                }
                Section {
                    Button("Удалить аккаунт", role: .destructive) { deleting = true }
                        .disabled(recorder.isRecording)
                } footer: {
                    Text("Аккаунт, все встречи, аудиозаписи, транскрипты и ссылки, которыми вы делились, удаляются без возможности восстановления.")
                }
            }
            .navigationTitle("Профиль")
            .refreshable { await session.refresh() }
            .sheet(isPresented: $deleting) { DeleteAccountView() }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { session.logout() }
            } message: {
                if !uploader.recordings.isEmpty {
                    Text("Неотправленные записи (\(uploader.recordings.count)) будут удалены с телефона.")
                }
            }
        }
    }
}
