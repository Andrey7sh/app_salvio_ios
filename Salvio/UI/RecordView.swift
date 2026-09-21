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
                    .foregroundColor(recorder.isRecording ? .primary : .secondary)
                    .accessibilityLabel("Длительность записи \(Format.duration(recorder.elapsed))")
                Text(statusText)
                    .foregroundColor(recorder.isCapturing || !recorder.isRecording ? .secondary : .orange)
                    .multilineTextAlignment(.center)

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

                if recorder.isRecording {
                    Button {
                        if recorder.isCapturing { recorder.pause() } else { recorder.resume() }
                    } label: {
                        Label(recorder.isCapturing ? "Пауза" : "Продолжить",
                              systemImage: recorder.isCapturing ? "pause.fill" : "play.fill")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.bordered)
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
        if recorder.isPausedByUser { return "Пауза. Запись сохранится целиком" }
        if recorder.isInterrupted { return "Микрофон занят, ждём и продолжим сами" }
        return "Идёт запись. Экран можно выключить, запись продолжится"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Профиль работы: \(session.user?.defaultScenario?.label ?? "не выбран")").font(.headline)
            Text("Профиль меняется в веб-кабинете").font(.footnote).foregroundColor(.secondary)
            if let balance = session.balance {
                Text("На балансе: \(balance.balanceMinutes) мин")
                if balance.lowBalance {
                    Text("Минут почти не осталось. Записи сохранятся и обработаются, когда минуты появятся")
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
