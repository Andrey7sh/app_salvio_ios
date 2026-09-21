import SwiftUI

/// Согласие на запись и на обработку аудио (App Store 2.5.14 и 5.1.2(i)):
/// спрашиваем до первой записи, показываем, кто обрабатывает данные, и даём отозвать согласие в профиле.
enum RecordingConsent {
    private static let key = "recordingConsentGranted"

    static var granted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct ConsentView: View {
    var onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Как Salvio работает с записью")
                        .font(.title3.bold())
                    row("mic.fill", "Запись начинается только по вашей кнопке и продолжается, пока вы её не остановите. Пока идёт запись, в приложении видна красная плашка, а на экране блокировки таймер.")
                    row("person.2.fill", "Предупредите собеседников, что встреча записывается. Соблюдение закона о записи разговоров на вашей стороне.")
                    row("icloud.and.arrow.up", "Аудио загружается на серверы Salvio в России, там получается транскрипт и итоги по вашему сценарию.")
                    row("cpu", "Распознавание речи и подготовку итогов выполняют подрядчики Salvio: сервис распознавания речи и языковая модель. Они обрабатывают аудио и текст встречи по договору и не используют их для обучения.")
                    row("trash", "Записи и аккаунт можно удалить в профиле. Согласие отзывается там же, после этого новые записи не создаются.")
                    Text("Подробности в [пользовательском соглашении и политике конфиденциальности](https://salvio.io/mob_terms).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        RecordingConsent.granted = true
                        appLog("consent", "согласие на запись и обработку получено")
                        dismiss()
                        onAccept()
                    } label: {
                        Text("Согласен, начать запись").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Не сейчас") { dismiss() }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Согласие")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundColor(.accentColor)
            Text(text)
        }
    }
}
