import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared
    @ObservedObject private var uploader = Uploader.shared
    @State private var confirmLogout = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
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
                    Link("Пользовательское соглашение", destination: URL(string: "https://salvio.io/mob_terms")!)
                    Link("Поддержка", destination: URL(string: "https://t.me/salvio_support_bot")!)
                    LabeledContent("Версия приложения", value: version)
                }
                Section {
                    Button("Выйти", role: .destructive) { confirmLogout = true }
                        .disabled(recorder.isRecording)
                } footer: {
                    if recorder.isRecording { Text("Остановите запись перед выходом") }
                }
            }
            .navigationTitle("Профиль")
            .refreshable { await session.refresh() }
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
