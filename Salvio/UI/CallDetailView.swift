import AVFoundation
import SwiftUI

@MainActor
final class CallDetailModel: ObservableObject {
    let id: String
    @Published var title: String
    @Published private(set) var detail: CallDetail?
    @Published private(set) var result: CallResult?
    @Published private(set) var checklist: Checklist?
    @Published private(set) var transcript: [TranscriptSegment] = []
    @Published private(set) var shareURL: URL?
    @Published private(set) var sharing = false
    @Published var error: String?

    init(call: CallItem) {
        id = call.id
        title = call.title ?? "Встреча"
    }

    var status: String? { detail?.status }

    func load() async {
        do {
            let d: CallDetail = try await APIClient.shared.send("GET", "calls/\(id)")
            detail = d
            title = d.title ?? title
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard status == "done" else { return }
        async let result = get("calls/\(id)/result", as: CallResult.self)
        async let checklist = get("calls/\(id)/checklist", as: ChecklistResponse.self)
        async let transcript = get("calls/\(id)/transcript", as: Transcript.self)
        async let share = get("calls/\(id)/share", as: ShareLookup.self)
        self.result = await result
        self.checklist = await checklist?.checklist
        self.transcript = await transcript?.segments ?? []
        if let url = await share?.share?.url { shareURL = URL(string: url) }
    }

    /// Публичная ссылка создаётся только по нажатию: без действия пользователя запись не публикуем.
    func createShare() async {
        struct Input: Encodable { let sections: [String] }
        sharing = true
        defer { sharing = false }
        do {
            let info: ShareLinkInfo = try await APIClient.shared.send("POST", "calls/\(id)/share", body: .json(Input(sections: ["summary"])))
            shareURL = info.url.flatMap(URL.init(string:))
            if shareURL == nil { error = "Не удалось создать ссылку" }
        } catch {
            self.error = "Не удалось создать ссылку"
        }
    }

    func rename(_ newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else { return }
        do {
            let _: StatusResponse = try await APIClient.shared.send("PATCH", "mobile/calls/\(id)/title", body: .form([("title", trimmed)]))
            title = trimmed
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        try? await APIClient.shared.send("GET", path)
    }
}

struct CallDetailView: View {
    @StateObject private var model: CallDetailModel
    @State private var renaming = false
    @State private var newTitle = ""

    init(call: CallItem) {
        _model = StateObject(wrappedValue: CallDetailModel(call: call))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.title).font(.title2.bold())
                if let d = model.detail {
                    Text([Format.date(d.startedAt), (d.durationSeconds ?? 0) > 0 ? Format.duration(Double(d.durationSeconds ?? 0)) : ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundColor(.secondary)
                }
                if let error = model.error {
                    Text(error).foregroundColor(.red)
                }
                statusBlock
                if model.status == "done" { resultBlock }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Детали встречи")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { newTitle = model.title; renaming = true } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Переименовать")
        }
        .alert("Название встречи", isPresented: $renaming) {
            TextField("Введите название...", text: $newTitle)
            Button("Сохранить") { Task { await model.rename(newTitle) } }
            Button("Отмена", role: .cancel) {}
        }
        .refreshable { await model.load() }
        .task {
            // Пока запись обрабатывается, опрашиваем раз в 10 секунд.
            repeat {
                await model.load()
                guard model.detail == nil || Format.isProcessing(model.status) else { break }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            } while !Task.isCancelled
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
        case "error"?:
            GroupBox {
                Text("Не удалось обработать запись. Напишите в поддержку, аудио сохранено на сервере.")
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

    @ViewBuilder private var resultBlock: some View {
        if let url = model.detail?.audioUrl.flatMap(URL.init(string:)) {
            AudioPlayerView(url: url, fallbackDuration: Double(model.detail?.durationSeconds ?? 0))
        }
        shareBlock
        if let label = model.result?.scenario?.label {
            Text(label).font(.subheadline).foregroundColor(.secondary)
        }
        let sections = (model.result?.sections ?? []).filter { !$0.text.isEmpty }
        if sections.isEmpty {
            Text(model.result?.error ?? "Итоги ещё не сформированы").foregroundColor(.secondary)
        }
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            GroupBox(section.title ?? "") {
                Text(section.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let checklist = model.checklist, !checklist.categories.isEmpty {
            ChecklistBlock(checklist: checklist)
        }
        if !model.transcript.isEmpty {
            GroupBox {
                DisclosureGroup("Транскрипт") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(model.transcript.enumerated()), id: \.offset) { _, seg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seg.speakerLabel ?? "").font(.caption.bold()).foregroundColor(.secondary)
                                Text(seg.text ?? "").textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var shareBlock: some View {
        if let url = model.shareURL {
            ShareLink(item: url,
                      subject: Text(model.title),
                      message: Text(Format.shareText(title: model.title, sections: model.result?.sections ?? []))) {
                Label("Поделиться", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Task { await model.createShare() }
                } label: {
                    Label(model.sharing ? "Создаём ссылку…" : "Поделиться записью", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.sharing)
                Text("Создаст публичную ссылку на итоги встречи, открыть её можно без регистрации")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }
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

