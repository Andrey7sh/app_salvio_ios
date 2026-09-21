import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared
    @ObservedObject private var uploader = Uploader.shared
    @State private var confirmLogout = false
    @State private var consentGranted = RecordingConsent.granted
    @State private var deleting = false
    @State private var writingSupport = false
    @State private var supportNote: String?

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
                    Link("Пользовательское соглашение", destination: URL(string: "https://salvio.io/terms")!)
                    Link("Политика конфиденциальности", destination: URL(string: "https://salvio.io/privacy")!)
                    Button("Написать в поддержку") {
                        if SupportMailView.canSend {
                            writingSupport = true
                        } else {
                            supportNote = Support.openMailtoOrCopy(email: session.user?.email)
                        }
                    }
                    NavigationLink("Диагностика") { DiagnosticsView() }
                    LabeledContent("Версия приложения", value: version)
                } footer: {
                    Text(supportNote ?? "К письму приложим журнал приложения: по нему видно, что происходило с записью и загрузкой.")
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
            .sheet(isPresented: $writingSupport) { SupportMailView(email: session.user?.email) }
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
