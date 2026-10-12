import SwiftUI
import UIKit

// MARK: Транскрипт

private struct IndexedSegment: Identifiable {
    let index: Int
    let segment: TranscriptSegment
    var id: Int { index }
}

struct TranscriptPane: View {
    @ObservedObject var model: CallDetailModel
    let onSpeakers: () -> Void
    @State private var query = ""

    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Реплики с индексом: подпись спикера ставим только на смене голоса, как в веб-кабинете.
    private var shown: [IndexedSegment] {
        model.transcript.enumerated()
            .filter { needle.isEmpty || ($0.element.text ?? "").lowercased().contains(needle) }
            .map { IndexedSegment(index: $0.offset, segment: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Поиск по тексту", text: $query).textFieldStyle(.roundedBorder)
                Button("Спикеры", action: onSpeakers).disabled(model.transcript.isEmpty)
            }
            if model.transcript.isEmpty {
                if model.transcriptLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if model.transcriptFailed {
                    retry("Не удалось загрузить транскрипт")
                } else {
                    Text("Транскрипт появится после обработки").foregroundColor(.secondary)
                }
            } else if !needle.isEmpty, shown.isEmpty, model.transcriptComplete {
                Text("Ничего не нашлось").foregroundColor(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { item in
                        let previous = item.index > 0 ? model.transcript[item.index - 1].speaker : nil
                        TranscriptRow(segment: item.segment,
                                      showSpeaker: !needle.isEmpty || item.segment.speaker != previous || item.index == 0,
                                      player: model.player) { model.playFrom(ms: $0) }
                            .onAppear {
                                if needle.isEmpty, item.index == model.transcript.count - 1 {
                                    Task { await model.loadTranscriptPage() }
                                }
                            }
                    }
                    if !model.transcriptComplete {
                        if model.transcriptFailed { retry("Не удалось загрузить продолжение") }
                        else { ProgressView().frame(maxWidth: .infinity).padding() }
                    }
                }
            }
        }
        // Поиск идёт по всей встрече: при первом вводе догружаем остальные страницы.
        .task(id: needle.isEmpty) { if !needle.isEmpty { await model.loadWholeTranscript() } }
    }

    private func retry(_ text: String) -> some View {
        HStack {
            Text(text).foregroundColor(.red)
            Spacer()
            Button("Повторить") { Task { await model.loadTranscriptPage() } }
        }
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment
    let showSpeaker: Bool
    let player: PlayerModel?
    let onSeek: (Int) -> Void

    var body: some View {
        if let player {
            HighlightedRow(segment: segment, showSpeaker: showSpeaker, player: player, onSeek: onSeek)
        } else {
            RowContent(segment: segment, showSpeaker: showSpeaker, active: false, onSeek: onSeek)
        }
    }
}

/// Отдельная вьюха подписана на плеер: подсветка обновляется, не перерисовывая весь список.
private struct HighlightedRow: View {
    let segment: TranscriptSegment
    let showSpeaker: Bool
    @ObservedObject var player: PlayerModel
    let onSeek: (Int) -> Void

    var body: some View {
        let start = segment.startMs ?? 0
        let end = segment.endMs ?? start
        let active = player.currentMs.map { $0 >= start && $0 < end } ?? false
        RowContent(segment: segment, showSpeaker: showSpeaker, active: active, onSeek: onSeek)
    }
}

private struct RowContent: View {
    let segment: TranscriptSegment
    let showSpeaker: Bool
    let active: Bool
    let onSeek: (Int) -> Void

    var body: some View {
        Button { onSeek(segment.startMs ?? 0) } label: {
            VStack(alignment: .leading, spacing: 2) {
                if showSpeaker {
                    HStack(spacing: 8) {
                        Text(segment.speakerLabel ?? segment.speaker ?? "Спикер").font(.subheadline.bold())
                        Text(Format.duration(Double(segment.startMs ?? 0) / 1000)).font(.caption.monospacedDigit()).foregroundColor(.accentColor)
                    }
                }
                Text(segment.text ?? "").foregroundColor(.primary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor.opacity(0.2) : Color.clear))
        }
        .buttonStyle(.plain)
        .padding(.top, showSpeaker ? 10 : 0)
        .accessibilityHint("Слушать с \(Format.duration(Double(segment.startMs ?? 0) / 1000))")
    }
}

// MARK: Спикеры

struct SpeakersSheet: View {
    @ObservedObject var model: CallDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var names: [String: String] = [:]
    @State private var roles: [String: String] = [:]

    /// Голоса из всего транскрипта: в первой странице может не оказаться того, кто заговорил позже.
    private var speakers: [String] {
        var seen: [String] = []
        for s in model.transcript { if let key = s.speaker, !seen.contains(key) { seen.append(key) } }
        return seen
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !model.transcriptComplete {
                        HStack { ProgressView(); Text("Догружаем транскрипт…") }
                    }
                } footer: {
                    Text(model.isDone ? "После сохранения итоги пересоберутся с новыми именами. Минуты не списываются."
                                      : "Имена появятся в транскрипте и в итогах.")
                }
                ForEach(speakers, id: \.self) { key in
                    Section {
                        TextField("Имя", text: Binding(get: { names[key] ?? "" }, set: { names[key] = String($0.prefix(80)) }))
                        if !model.roleOptions.isEmpty {
                            Picker("Роль", selection: Binding(get: { roles[key] ?? "" }, set: { roles[key] = $0.isEmpty ? nil : $0 })) {
                                Text("Без роли").tag("")
                                ForEach(model.roleOptions) { Text($0.title).tag($0.id) }
                            }
                        }
                    } header: {
                        Text("Голос \(key)")
                    } footer: {
                        Text("«" + model.transcript.filter { $0.speaker == key }.prefix(2).map { String(($0.text ?? "").prefix(80)) }.joined(separator: " … ") + "»")
                    }
                }
            }
            .navigationTitle("Спикеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = names, r = roles
                        dismiss()
                        Task { await model.saveSpeakers(names: n, roles: r) }
                    }
                    .disabled(speakers.isEmpty)
                }
            }
            .task { await model.loadWholeTranscript() }
            // Окно могли открыть до первой страницы: сохранённые имена подхватываем, когда они придут,
            // иначе сохранение заменило бы их пустыми (сервер хранит карту целиком).
            .onAppear { names = model.speakerNames; roles = model.speakerRoles }
            .onChange(of: model.speakerNames) { names = $0 }
            .onChange(of: model.speakerRoles) { roles = $0 }
        }
    }
}

// MARK: Чат

struct ChatPane: View {
    @ObservedObject var model: CallDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Спросите что угодно о встрече: о чём договорились, какие цифры звучали, что ответить клиенту. До 50 вопросов в день.")
                .font(.footnote).foregroundColor(.secondary)
            ForEach(Array(model.chat.enumerated()), id: \.offset) { _, message in
                let mine = message.role == "user"
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    Text(markdown(message.content))
                        .textSelection(.enabled)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(mine ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                    if !mine, !message.id.hasPrefix("pending") {
                        Button("Сохранить в итоги") { Task { await model.saveAnswer(message.id) } }.font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            }
            if model.chatSending {
                HStack { ProgressView(); Text("Думаю, это может занять до минуты…").font(.footnote) }
            }
        }
    }

    /// Ответ приходит Markdown-строкой; не разобралась: показываем как есть.
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: Ссылка

struct ShareSheet: View {
    @ObservedObject var model: CallDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ShareSection.allCases) { section in
                        Toggle(section.title, isOn: Binding(
                            get: { picked.contains(section.rawValue) },
                            set: { if $0 { picked.insert(section.rawValue) } else { picked.remove(section.rawValue) } }))
                    }
                } header: {
                    Text("Что показать по ссылке")
                } footer: {
                    Text("Публичная ссылка открывается без регистрации.")
                }
                Section {
                    if let url = model.shareURL {
                        ShareLink(item: url, subject: Text(model.title), message: Text(model.title)) {
                            Label("Отправить ссылку", systemImage: "link")
                        }
                    }
                    Button(model.shareURL == nil ? "Создать ссылку" : "Обновить разделы ссылки") {
                        Task { await model.createShare(sections: ShareSection.allCases.map(\.rawValue).filter(picked.contains)) }
                    }
                    .disabled(picked.isEmpty || model.sharing)
                    ShareLink(item: model.shareText) { Label("Отправить итоги текстом, без ссылки", systemImage: "text.alignleft") }
                    if model.shareURL != nil {
                        Button("Закрыть доступ по ссылке", role: .destructive) { Task { await model.revokeShare() } }
                    }
                }
            }
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .onAppear { picked = Set(model.shareSections.isEmpty ? ["summary"] : model.shareSections) }
        }
    }
}

// MARK: Выбор шаблона

/// Шаблоны итогов: на экране записи, в профиле и для «Итоги по другому шаблону».
/// Список короткий (десятки шаблонов), поэтому грузим целиком и ищем по нему на телефоне.
struct ScenarioPickerView: View {
    let title: String
    let onPick: (ScenarioCard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var all: [ScenarioCard]?
    @State private var error: String?
    @State private var query = ""

    private var shown: [ScenarioCard] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return (all ?? []).filter { needle.isEmpty || "\($0.name ?? "") \($0.description ?? "")".lowercased().contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error, all == nil { Text(error).foregroundColor(.red) }
                if all == nil, error == nil { ProgressView().frame(maxWidth: .infinity) }
                ForEach(shown) { scenario in
                    Button {
                        dismiss()
                        onPick(scenario)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.label).foregroundColor(.primary)
                            if let d = scenario.description, !d.isEmpty {
                                Text(d).font(.footnote).foregroundColor(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                if all != nil, shown.isEmpty { Text("Ничего не нашлось").foregroundColor(.secondary) }
            }
            .searchable(text: $query, prompt: "Найти шаблон")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .task {
                do {
                    // Популярные первыми, остальные следом без повторов.
                    let popular = (try? await MeetingAPI.popularScenarios()) ?? []
                    let rest = try await MeetingAPI.scenarios().filter { s in !popular.contains { $0.id == s.id } }
                    all = popular + rest
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

/// Системное «Поделиться» для файла экспорта.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
