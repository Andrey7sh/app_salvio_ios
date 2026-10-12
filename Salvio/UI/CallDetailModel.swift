import Foundation

enum DetailTab: String, CaseIterable, Identifiable {
    case summary = "Итоги", transcript = "Транскрипт", chat = "Спросить ИИ"
    var id: String { rawValue }
}

@MainActor
final class CallDetailModel: ObservableObject {
    let id: String
    @Published var title: String
    @Published private(set) var detail: CallDetail?
    @Published private(set) var result: CallResult?
    @Published private(set) var checklist: Checklist?
    @Published private(set) var recommendations: [RecommendationTip] = []
    @Published private(set) var player: PlayerModel?
    @Published var tab: DetailTab = .summary
    @Published var error: String?
    /// Итог действия для всплывающего сообщения: успех («Перенесено в папку») или текст ошибки.
    /// error остаётся для загрузки экрана: он виден в шапке, а действие могли сделать, пролистав вниз.
    @Published var notice: String?
    /// Запись ушла в корзину: экран закрывается.
    @Published private(set) var trashed = false

    // Транскрипт страницами по MeetingAPI.transcriptPage реплик.
    @Published private(set) var transcript: [TranscriptSegment] = []
    @Published private(set) var transcriptTotal: Int?
    @Published private(set) var transcriptLoading = false
    @Published private(set) var transcriptFailed = false
    /// Растёт при сбросе транскрипта: ответ на страницу, запрошенную до сброса, отбрасывается.
    private var transcriptGen = 0
    @Published private(set) var speakerNames: [String: String] = [:]
    @Published private(set) var speakerRoles: [String: String] = [:]
    @Published private(set) var roleOptions: [Preferences.SpeakerRole] = []
    @Published private(set) var restarting = false
    /// Растёт при перезапуске обработки: экран заново запускает опрос статуса.
    @Published private(set) var pollGeneration = 0

    @Published private(set) var summaries: [SummaryTab] = []
    @Published var selectedSummaryId: String?

    @Published private(set) var chat: [ChatMessage] = []
    @Published private(set) var chatLoaded = false
    @Published private(set) var chatSending = false

    @Published private(set) var shareURL: URL?
    @Published private(set) var shareSections: [String] = []
    @Published private(set) var sharing = false
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var exporting = false
    @Published var exportFile: URL?

    init(call: CallItem) {
        id = call.id
        title = call.title ?? "Встреча"
    }

    var status: String? { detail?.status }
    var isDone: Bool { status == "done" }
    var transcriptComplete: Bool { transcriptTotal.map { transcript.count >= $0 } ?? false }
    var selectedSummary: SummaryTab? { summaries.first { $0.id == selectedSummaryId && $0.isPrimary != true } }

    func load() async {
        do {
            let d: CallDetail = try await APIClient.shared.send("GET", "calls/\(id)")
            // Presigned-ссылка новая на каждый ответ: сравниваем путь, иначе обновление сбрасывало бы плеер.
            if let url = d.audioUrl.flatMap(URL.init(string:)), player?.url.path != url.path {
                player?.teardown()
                player = PlayerModel(url: url, fallbackDuration: Double(d.durationSeconds ?? 0))
            }
            detail = d
            title = d.title ?? title
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard isDone else { return }
        async let result = get("calls/\(id)/result", as: CallResult.self)
        async let checklist = get("calls/\(id)/checklist", as: ChecklistResponse.self)
        async let recommendations = get("calls/\(id)/recommendations", as: RecommendationsResponse.self)
        async let share = try? MeetingAPI.share(id)
        async let summaries = try? MeetingAPI.summaries(id)
        self.result = await result
        self.checklist = await checklist?.checklist
        self.recommendations = await recommendations?.recommendations?.tips ?? []
        // try? схлопывает Optional: сбой сети и «ссылки нет» выглядят одинаково, ссылка просто не показывается.
        let info = await share
        shareURL = info?.url.flatMap(URL.init(string:))
        shareSections = info?.sections ?? []
        if let list = await summaries { self.summaries = list }
        // Транскрипт мог устареть (новые имена, повторное распознавание): сбрасываем, грузим при открытой вкладке.
        resetTranscript()
        if tab == .transcript { await loadTranscriptPage() }
    }

    func select(_ tab: DetailTab) async {
        self.tab = tab
        if tab == .transcript, transcript.isEmpty {
            Analytics.track("transcript_open")
            await loadTranscriptPage()
        }
        if tab == .chat, !chatLoaded { await loadChat() }
    }

    // MARK: Транскрипт

    func loadTranscriptPage() async {
        guard !transcriptLoading, !transcriptComplete else { return }
        let gen = transcriptGen
        transcriptLoading = true
        transcriptFailed = false
        let offset = transcript.count
        defer { if gen == transcriptGen { transcriptLoading = false } }
        do {
            let page = try await MeetingAPI.transcript(id, offset: offset)
            // Сброс или параллельная догрузка за время запроса: ответ устарел.
            guard gen == transcriptGen, offset == transcript.count else { return }
            transcript += page.segments
            // Без total (старый бэкенд, 202 на обработке) считаем, что больше нет.
            transcriptTotal = page.total ?? transcript.count
            speakerNames = page.speakerNames
            speakerRoles = page.speakerRoles
        } catch {
            if gen == transcriptGen { transcriptFailed = true }
        }
        if roleOptions.isEmpty, let prefs = try? await MeetingAPI.preferences() {
            roleOptions = prefs.speakerRoles ?? []
        }
    }

    /// Список голосов и поиск по тексту нужны по всей встрече: догружаем оставшиеся страницы.
    func loadWholeTranscript() async {
        while !transcriptComplete, !transcriptFailed, !Task.isCancelled {
            await loadTranscriptPage()
            // Страницу мог уже грузить список: без паузы цикл крутился бы на главном потоке.
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func resetTranscript() {
        transcriptGen += 1
        transcriptLoading = false
        transcript = []
        transcriptTotal = nil
        transcriptFailed = false
    }

    func playFrom(ms: Int) {
        Analytics.track("transcript_seek")
        player?.play(fromMs: ms)
    }

    // MARK: Спикеры

    /// Имена применяются при чтении, а готовые итоги остаются со старыми метками. Решение 12.10:
    /// после сохранения пересобираем итоги без повторного распознавания, минуты второй раз не списываются.
    func saveSpeakers(names: [String: String], roles: [String: String]) async {
        let clean = names.mapValues { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.value.isEmpty }
        guard clean != speakerNames || roles != speakerRoles else { return }
        do {
            try await MeetingAPI.saveSpeakers(id, names: clean, roles: roles)
            Analytics.track("speakers_saved")
            resetTranscript()
            if isDone { await restart(retranscribe: false, notice: "Итоги обновляются с новыми именами") }
            // Новые имена сразу; если перезапуск отклонили (402 на частично оплаченной записи), транскрипт не пропадает.
            await loadTranscriptPage()
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Обработка, корзина, папки

    func restart(retranscribe: Bool, notice: String = "Запись отправлена на повторную обработку") async {
        guard !restarting else { return }
        restarting = true
        defer { restarting = false }
        do {
            _ = try await MeetingAPI.restart(id, retranscribe: retranscribe)
            self.notice = notice
            resetTranscript()
            pollGeneration += 1
        } catch {
            self.notice = error.localizedDescription
        }
    }

    func trash() async {
        do {
            try await MeetingAPI.trash(id)
            trashed = true
        } catch {
            notice = error.localizedDescription
        }
    }

    func loadFolders() async {
        folders = (try? await MeetingAPI.folders().folders) ?? []
    }

    func move(to folder: Folder?) async {
        do {
            try await MeetingAPI.move(id, to: folder?.id)
            notice = folder.map { "Перенесено в «\($0.name)»" } ?? "Запись без папки"
        } catch {
            notice = error.localizedDescription
        }
    }

    func createFolderAndMove(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let folder = try await MeetingAPI.createFolder(String(trimmed.prefix(120)))
            folders.append(folder)
            await move(to: folder)
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Чат

    func loadChat() async {
        do {
            chat = try await MeetingAPI.chat(id)
            chatLoaded = true
        } catch {
            notice = error.localizedDescription
        }
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !chatSending else { return }
        // Вопрос показываем сразу: ответ генерируется до минуты.
        let pending = ChatMessage(id: "pending-" + UUID().uuidString, role: "user", content: q)
        chat.append(pending)
        chatSending = true
        defer { chatSending = false }
        do {
            let answer = try await MeetingAPI.ask(id, q)
            chat.append(answer)
            Analytics.track("chat_ask")
        } catch {
            // Вопрос без ответа убираем, иначе он висит в ленте как заданный.
            chat.removeAll { $0.id == pending.id }
            notice = error.localizedDescription
        }
    }

    func saveAnswer(_ messageId: String) async {
        do {
            try await MeetingAPI.saveAnswer(id, messageId: messageId)
            notice = "Ответ сохранён отдельной вкладкой в итогах"
            summaries = (try? await MeetingAPI.summaries(id)) ?? summaries
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Вкладки итогов

    /// Итоги по другому шаблону собираются около минуты: опрашиваем, пока есть незавершённые.
    func addSummary(scenarioId: String) async {
        do {
            let tab = try await MeetingAPI.addSummary(id, scenarioId: scenarioId)
            summaries.append(tab)
            selectedSummaryId = tab.id
            // Не дольше трёх минут: зависшая очередь не должна опрашивать сервер вечно.
            for _ in 0..<36 where !Task.isCancelled && summaries.contains(where: { $0.pending }) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                summaries = (try? await MeetingAPI.summaries(id)) ?? summaries
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    func makePrimary(_ summaryId: String) async {
        do {
            try await MeetingAPI.makePrimary(id, summaryId: summaryId)
            notice = "Эти итоги теперь основные"
            selectedSummaryId = nil
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: Ссылка и экспорт

    /// Публичная ссылка создаётся только по нажатию: без действия пользователя запись не публикуем.
    func createShare(sections: [String]) async {
        guard !sharing, !sections.isEmpty else { return }
        sharing = true
        defer { sharing = false }
        do {
            let info = try await MeetingAPI.createShare(id, sections: sections)
            shareURL = info.url.flatMap(URL.init(string:))
            shareSections = sections
            if shareURL == nil { notice = "Не удалось создать ссылку" } else { Analytics.track("share") }
        } catch {
            notice = "Не удалось создать ссылку"
        }
    }

    func revokeShare() async {
        do {
            try await MeetingAPI.revokeShare(id)
            shareURL = nil
            shareSections = []
            notice = "Ссылка больше не открывается"
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Текст итогов для отправки без ссылки: открытая вкладка или основные.
    var shareText: String {
        Format.shareText(title: title, sections: selectedSummary?.sections ?? result?.sections ?? [])
    }

    func export(what: String, fmt: String) async {
        guard !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            exportFile = try await MeetingAPI.export(id, what: what, fmt: fmt, title: title, summaryId: selectedSummary?.id)
            Analytics.track("export")
        } catch {
            notice = error.localizedDescription
        }
    }

    func rename(_ newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else { return }
        do {
            let _: StatusResponse = try await APIClient.shared.send("PATCH", "mobile/calls/\(id)/title", body: .form([("title", trimmed)]))
            title = trimmed
        } catch {
            notice = error.localizedDescription
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        try? await APIClient.shared.send("GET", path)
    }
}
