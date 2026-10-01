import SwiftUI

struct RecordView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared
    @State private var askConsent = false
    @State private var choosingSpace = false
    @State private var zeroWarning: (current: String, workspace: String, name: String, minutes: Int)?
    @State private var switchError: String?

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
                    if recorder.isRecording {
                        recorder.stop()
                    } else if RecordingConsent.granted {
                        Task { await prepareAndStart() }
                    } else {
                        askConsent = true
                    }
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
            .sheet(isPresented: $askConsent) {
                ConsentView { Task { await prepareAndStart() } }
            }
            .alert(zeroWarning.map { "В «\($0.current)» 0 минут" } ?? "", isPresented: Binding(
                get: { zeroWarning != nil }, set: { if !$0 { zeroWarning = nil } })
            ) {
                if let w = zeroWarning {
                    Button("В «\(w.name)»") { zeroWarning = nil; Task { await recorder.start(workspace: w.workspace) } }
                    Button("Всё равно сюда") { zeroWarning = nil; Task { await recorder.start(workspace: session.workspaces?.current) } }
                    Button("Отмена", role: .cancel) { zeroWarning = nil }
                }
            } message: {
                if let w = zeroWarning {
                    Text("Запись сохранится и обработается после пополнения. Записать в «\(w.name)», там \(w.minutes) мин?")
                }
            }
            .confirmationDialog("Куда писать", isPresented: $choosingSpace, titleVisibility: .visible) {
                Button("👤 Личное") { switchTo(Workspaces.personalKey) }
                if let team = session.workspaces?.team {
                    Button("👥 \(team.name)") { switchTo(Workspaces.teamKey) }
                }
            } message: {
                Text("Сменится и в веб-кабинете. Уже начатые записи остаются там, где их начали.")
            }
        }
    }

    /// Правило 6 ТЗ пространств: перед записью в пространство с нулём предложить второе, где минуты есть.
    private func prepareAndStart() async {
        await session.refreshWorkspaces()
        if let ws = session.workspaces, ws.minutes == 0, let other = ws.other, other.minutes > 0 {
            zeroWarning = (ws.currentName, other.workspace, other.name, other.minutes)
            return
        }
        await recorder.start(workspace: session.workspaces?.current)
    }

    private func switchTo(_ workspace: String) {
        Task {
            do { try await session.switchWorkspace(workspace); switchError = nil }
            catch { switchError = "Не удалось сменить пространство" }
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
            if let ws = session.workspaces {
                HStack {
                    Text("Пространство: \(ws.inTeam ? "👥" : "👤") \(ws.currentName)")
                    if ws.team != nil && !recorder.isRecording {
                        Button("Сменить") { choosingSpace = true }.font(.subheadline)
                    }
                }
                if let team = ws.team, ws.teamShared {
                    // Два баланса всегда рядом, тот, что тратит текущее пространство, выделен.
                    Text("Личные: \(ws.personal.balanceMinutes) мин")
                        .fontWeight(ws.wallet == Workspaces.teamKey ? .regular : .semibold)
                        .foregroundColor(ws.wallet == Workspaces.teamKey ? .secondary : .primary)
                    Text("«\(team.name)»: \(team.balanceMinutes) мин")
                        .fontWeight(ws.wallet == Workspaces.teamKey ? .semibold : .regular)
                        .foregroundColor(ws.wallet == Workspaces.teamKey ? .primary : .secondary)
                } else {
                    Text("На балансе: \(ws.personal.balanceMinutes) мин")
                    if let team = ws.team {
                        Text("Общие для «Личное» и «\(team.name)», пока в команде нет сотрудников")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                if ws.low {
                    Text("Минут почти не осталось. Записи сохранятся и обработаются, когда минуты появятся")
                        .font(.footnote).foregroundColor(.orange)
                }
                if let switchError {
                    Text(switchError).font(.footnote).foregroundColor(.red)
                }
            } else {
                Text("Баланс минут: загружаем").foregroundColor(.secondary)
            }
            if session.user?.emailVerified == false {
                VerifyEmailNotice().font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

/// Напоминание подтвердить почту с кнопкой повторной отправки. Из приложения почту не подтверждал никто,
/// пока здесь была одна строка без действия. После отправки кнопка прячется, чтобы не слать пачку писем.
struct VerifyEmailNotice: View {
    @EnvironmentObject private var session: AppSession
    @State private var sent = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sent ? "Письмо отправлено. Если его нет во «Входящих», проверьте «Спам»"
                      : "Подтвердите почту по письму, чтобы получить 30 бесплатных минут")
                .foregroundColor(.orange)
            if !sent {
                Button("Отправить письмо ещё раз") { resend() }.disabled(sending)
            }
            if let error {
                Text(error).foregroundColor(.red)
            }
        }
    }

    private func resend() {
        sending = true
        Task {
            do { try await session.resendVerifyEmail(); sent = true; error = nil }
            catch { self.error = "Не удалось отправить письмо, попробуйте позже" }
            sending = false
        }
    }
}
