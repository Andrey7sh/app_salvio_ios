import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                header
                Spacer()
                Text(Format.duration(recorder.elapsed))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .accessibilityLabel("Длительность записи \(Format.duration(recorder.elapsed))")
                Text(statusText).foregroundColor(.secondary)

                Button {
                    if recorder.isRecording { recorder.stop() } else { Task { await recorder.start() } }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 120)
                        .background(Circle().fill(recorder.isRecording ? Color.red : Color.accentColor))
                }
                .accessibilityLabel(recorder.isRecording ? "Остановить запись" : "Начать запись")

                if recorder.isInterrupted {
                    Button("Продолжить") { recorder.resume() }.buttonStyle(.borderedProminent)
                }
                if let message = recorder.errorMessage {
                    Text(message).foregroundColor(.red).multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Запись")
            .task { await session.refresh() }
        }
    }

    private var statusText: String {
        guard recorder.isRecording else { return "Нажмите, чтобы начать запись" }
        if recorder.isInterrupted { return "Запись на паузе: микрофон занят" }
        return "Идет запись... Экран можно выключить, запись продолжится"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Профиль работы: \(session.user?.defaultScenario?.label ?? "не выбран")").font(.headline)
            Text("Профиль меняется в веб-кабинете").font(.footnote).foregroundColor(.secondary)
            if let balance = session.balance {
                Text("На балансе: \(balance.balanceMinutes) мин")
                if balance.lowBalance {
                    Text("Минут почти не осталось. Записи без минут сохранятся и обработаются после пополнения в веб-кабинете")
                        .font(.footnote).foregroundColor(.orange)
                }
            } else {
                Text("Баланс минут: загружаем").foregroundColor(.secondary)
            }
            if session.user?.emailVerified == false {
                Text("Подтвердите почту по письму, чтобы получить 30 бесплатных минут").font(.footnote).foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
