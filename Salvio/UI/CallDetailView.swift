import SwiftUI

struct CallDetailView: View {
    @StateObject private var model: CallDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var sheet: DetailSheet?
    @State private var confirmDelete = false
    @State private var choosingExport = false
    @State private var choosingFolder = false
    @State private var namingFolder = false
    @State private var folderName = ""
    @State private var question = ""

    enum DetailSheet: String, Identifiable {
        case speakers, share, addSummary
        var id: String { rawValue }
    }

    init(call: CallItem) {
        _model = StateObject(wrappedValue: CallDetailModel(call: call))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusBlock
                if let player = model.player, model.isDone || model.status == "error" {
                    AudioPlayerView(player: player)
                }
                if model.isDone {
                    OnboardingTip(.detailsTabs) {
                        Picker("Раздел", selection: Binding(get: { model.tab }, set: { tab in Task { await model.select(tab) } })) {
                            ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    switch model.tab {
                    case .summary: summaryPane
                    case .transcript: TranscriptPane(model: model) { sheet = .speakers }
                    case .chat: ChatPane(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if model.isDone && model.tab == .chat { chatInput }
        }
        .navigationTitle("Детали встречи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .alert("Название встречи", isPresented: $renaming) {
            TextField("Введите название...", text: $newTitle)
            Button("Сохранить") { Task { await model.rename(newTitle) } }
            Button("Отмена", role: .cancel) {}
        }
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .alert("Новая папка", isPresented: $namingFolder) {
            TextField("Название", text: $folderName)
            Button("Создать и перенести") { Task { await model.createFolderAndMove(folderName) } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await model.trash() } }
        } message: {
            Text("Запись уйдёт в корзину. 30 дней её можно вернуть из папок на экране встреч, потом она удалится навсегда.")
        }
        .confirmationDialog("Скачать файлом", isPresented: $choosingExport, titleVisibility: .visible) {
            // Форматы как в веб-кабинете (salvio-web services/export.py). PDF там это печать html, на телефоне не нужен.
            // У старых записей без строки итогов сервер отвечает 404: не предлагаем то, чего нет.
            if model.selectedSummary != nil || model.summaries.contains(where: { $0.isPrimary == true }) {
                Button("Итоги · Word") { export("summary", "docx") }
                Button("Итоги · текст") { export("summary", "txt") }
                Button("Итоги · Markdown") { export("summary", "md") }
            }
            Button("Транскрипт · Word") { export("transcript", "docx") }
            Button("Транскрипт · текст") { export("transcript", "txt") }
            Button("Транскрипт · субтитры SRT") { export("transcript", "srt") }
        }
        .confirmationDialog("Перенести в папку", isPresented: $choosingFolder, titleVisibility: .visible) {
            Button("Без папки") { Task { await model.move(to: nil) } }
            ForEach(model.folders) { folder in
                Button(folder.name) { Task { await model.move(to: folder) } }
            }
            Button("Новая папка…") { folderName = ""; namingFolder = true }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .speakers: SpeakersSheet(model: model)
            case .share: ShareSheet(model: model)
            case .addSummary:
                ScenarioPickerView(title: "Итоги по другому шаблону") { scenario in
                    Task { await model.addSummary(scenarioId: scenario.id) }
                }
            }
        }
        .sheet(item: Binding(get: { model.exportFile.map(IdentifiedURL.init) }, set: { model.exportFile = $0?.url })) {
            ActivityView(items: [$0.url])
        }
        .onChange(of: model.trashed) { trashed in if trashed { dismiss() } }
        .onDisappear { model.player?.pause() }
        .refreshable { await model.load() }
        .task { Analytics.track("meeting_open") }
        .task(id: model.pollGeneration) {
            // Пока запись обрабатывается, опрашиваем раз в 10 секунд. Перезапуск обработки начинает опрос заново.
            repeat {
                await model.load()
                guard model.detail == nil || Format.isProcessing(model.status) else { break }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            } while !Task.isCancelled
        }
    }

    private func export(_ what: String, _ fmt: String) {
        Task { await model.export(what: what, fmt: fmt) }
    }

    // MARK: Шапка и статус

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.title).font(.title2.bold())
            if let d = model.detail {
                Text([Format.date(d.startedAt), (d.durationSeconds ?? 0) > 0 ? Format.duration(Double(d.durationSeconds ?? 0)) : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundColor(.secondary)
            }
            if let error = model.error {
                Text(error).foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private var statusBlock: some View {
        switch model.status {
        case "awaiting_payment"?:
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Недостаточно минут на балансе", systemImage: "exclamationmark.circle").font(.headline)
                    // App Store 3.1.3(f): без призывов к оплате вне приложения, только состояние.
                    Text("Запись сохранена и обработается, когда минуты появятся.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "error"? where model.detail?.errorCode == "no_speech":
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("В записи не слышно речи", systemImage: "mic.slash").font(.headline)
                    Text("Проверьте, что микрофон не закрыт и телефон не в кармане. Минуты за эту запись не списаны.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "error"?:
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Не удалось обработать запись", systemImage: "exclamationmark.triangle").font(.headline)
                    Text("Аудио сохранено на сервере. Попробуйте обработать её заново.")
                    Button(model.restarting ? "Отправляем…" : "Обработать заново") {
                        Task { await model.restart(retranscribe: true) }
                    }
                    .disabled(model.restarting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "done"?, nil:
            EmptyView()
        default:
            HStack(spacing: 12) {
                ProgressView()
                Text("Встреча обрабатывается… \(Format.status(model.status))").foregroundColor(.secondary)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isDone {
                Button { sheet = .share } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Поделиться")
            }
            OnboardingTip(.detailsMenu, enabled: model.isDone) {
                Menu {
                    Button { newTitle = model.title; renaming = true } label: { Label("Переименовать", systemImage: "pencil") }
                    if model.isDone {
                        Button {
                            Task { await model.select(.transcript) }
                            sheet = .speakers
                        } label: { Label("Спикеры", systemImage: "person.2") }
                        Button { choosingExport = true } label: { Label("Скачать файлом", systemImage: "arrow.down.doc") }
                            .disabled(model.exporting)
                        Button { sheet = .addSummary } label: { Label("Итоги по другому шаблону", systemImage: "doc.badge.plus") }
                        Button { Task { await model.restart(retranscribe: false) } } label: {
                            Label("Пересобрать итоги", systemImage: "arrow.clockwise")
                        }
                    }
                    // Запись без речи сервер распознавать заново не даёт (400 no_speech).
                    if model.isDone || (model.status == "error" && model.detail?.errorCode != "no_speech") {
                        Button { Task { await model.restart(retranscribe: true) } } label: {
                            Label("Распознать заново", systemImage: "waveform")
                        }
                    }
                    if model.detail != nil {
                        Button {
                            Task { await model.loadFolders() }
                            choosingFolder = true
                        } label: { Label("Перенести в папку", systemImage: "folder") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ещё")
            }
        }
    }

    // MARK: Итоги

    @ViewBuilder private var summaryPane: some View {
        let primaryId = model.summaries.first { $0.isPrimary == true }?.id
        if model.summaries.count > 1 || model.selectedSummaryId != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // У старых записей основных итогов в списке вкладок может не быть: без этой кнопки к ним не вернуться.
                    if primaryId == nil {
                        chip("★ Основные", selected: model.selectedSummaryId == nil) { model.selectedSummaryId = nil }
                    }
                    ForEach(model.summaries) { tab in
                        let selected = (model.selectedSummaryId ?? primaryId) == tab.id
                        chip((tab.isPrimary == true ? "★ " : "") + (tab.title ?? "Итоги"), selected: selected) {
                            model.selectedSummaryId = tab.isPrimary == true ? nil : tab.id
                        }
                    }
                }
            }
        }
        if let extra = model.selectedSummary {
            extraSummary(extra)
        } else {
            mainSummary
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func extraSummary(_ tab: SummaryTab) -> some View {
        if tab.pending {
            HStack(spacing: 12) {
                ProgressView()
                Text("Итоги по шаблону «\(tab.title ?? "")» собираются, это займёт около минуты").foregroundColor(.secondary)
            }
        } else if tab.status == "failed" {
            Text(tab.error ?? "Не удалось собрать итоги").foregroundColor(.secondary)
        } else {
            sections(tab.sections ?? [])
            if tab.kind != "chat" {
                Button("Сделать основными") { Task { await model.makePrimary(tab.id) } }
            }
        }
    }

    @ViewBuilder private var mainSummary: some View {
        if let label = model.result?.scenario?.label {
            Text(label).font(.subheadline).foregroundColor(.secondary)
        }
        let list = (model.result?.sections ?? []).filter { !$0.text.isEmpty }
        if list.isEmpty {
            Text(model.result?.error ?? "Итоги ещё не сформированы").foregroundColor(.secondary)
        }
        sections(list)
        Button("+ Итоги по другому шаблону") { sheet = .addSummary }
        GroupBox("Рекомендации тренера") {
            VStack(alignment: .leading, spacing: 12) {
                if model.recommendations.isEmpty {
                    Text("Сейчас тут пусто").foregroundColor(.secondary)
                }
                ForEach(Array(model.recommendations.enumerated()), id: \.offset) { _, tip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title ?? "").font(.subheadline.bold())
                        Text(tip.description ?? "").textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let checklist = model.checklist, !checklist.categories.isEmpty {
            ChecklistBlock(checklist: checklist)
        }
    }

    private func sections(_ list: [ResultSection]) -> some View {
        ForEach(Array(list.filter { !$0.text.isEmpty }.enumerated()), id: \.offset) { _, section in
            GroupBox(section.title ?? "") {
                Text(section.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Чат

    private var chatInput: some View {
        HStack {
            TextField("Вопрос о встрече", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                let q = question
                question = ""
                Task { await model.ask(q) }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.chatSending)
            .accessibilityLabel("Отправить вопрос")
        }
        .padding()
        .background(.bar)
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ChecklistBlock: View {
    let checklist: Checklist

    var body: some View {
        GroupBox(checklist.checklistName ?? "Чек-лист") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(checklist.categories.enumerated()), id: \.offset) { _, category in
                    if let name = category.name { Text(name).font(.subheadline.bold()) }
                    ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top) {
                            Text(item.criterion ?? "")
                            Spacer()
                            Text(item.verdict)
                                .foregroundColor(item.verdict == "Да" ? .green : item.verdict == "Частично" ? .orange : .red)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
