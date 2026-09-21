import SwiftUI

@MainActor
final class CallsModel: ObservableObject {
    @Published private(set) var items: [CallItem] = []
    @Published private(set) var loaded = false
    /// Список взят из кэша: сервер недоступен.
    @Published private(set) var offline = false
    @Published var error: String?
    private var page = 0
    private var totalPages = 1
    private var loading = false

    func reload() async {
        page = 0
        totalPages = 1
        await loadMore(reset: true)
    }

    func loadMore(reset: Bool = false) async {
        guard !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let result: CallsPage = try await APIClient.shared.send("GET", "calls?page=\(page + 1)&limit=20")
            items = reset ? result.items : items + result.items.filter { new in !items.contains { $0.id == new.id } }
            page = result.page
            totalPages = result.totalPages
            error = nil
            offline = false
            if page == 1 { CallsCache.save(items) }
        } catch {
            let cached = CallsCache.load()
            if reset, !cached.isEmpty {
                items = cached
                offline = true
                self.error = nil
            } else {
                self.error = error.localizedDescription
            }
        }
        loaded = true
    }
}

struct CallsListView: View {
    @StateObject private var model = CallsModel()
    @ObservedObject private var uploader = Uploader.shared

    var body: some View {
        NavigationStack {
            List {
                if !uploader.recordings.isEmpty {
                    Section("На телефоне") {
                        ForEach(uploader.recordings) { rec in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rec.title)
                                Text(localStatus(rec)).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if let error = model.error {
                    Text(error).foregroundColor(.red)
                }
                if model.offline {
                    Label("Нет связи с сервером, показаны сохранённые встречи", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section {
                    ForEach(model.items) { item in
                        NavigationLink(value: item) { CallRow(item: item) }
                            .onAppear {
                                if item.id == model.items.last?.id { Task { await model.loadMore() } }
                            }
                    }
                }
            }
            .overlay {
                if model.loaded, model.items.isEmpty, uploader.recordings.isEmpty, model.error == nil {
                    VStack(spacing: 8) {
                        Text("Записанных встреч пока нет").font(.headline)
                        Text("Нажмите «Начать запись», чтобы создать первую встречу").foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                }
            }
            .refreshable {
                uploader.kick()
                await model.reload()
            }
            .navigationTitle("Встречи")
            .navigationDestination(for: CallItem.self) { CallDetailView(call: $0) }
            .task { await model.reload() }
            .onChange(of: uploader.completedCount) { _ in Task { await model.reload() } }
        }
    }

    private func localStatus(_ rec: Recording) -> String {
        if rec.openChunk != nil || !rec.isFinished { return "Идет запись..." }
        return rec.uploaded.isEmpty ? "Ожидает отправки" : "Выгружается... \(rec.uploaded.count) из \(rec.chunkCount)"
    }
}

private struct CallRow: View {
    let item: CallItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? "Встреча").lineLimit(2)
            HStack {
                Text(Format.date(item.startedAt))
                if let d = item.durationSeconds, d > 0 { Text("· \(Format.duration(Double(d)))") }
                Spacer()
                Text(Format.status(item.status))
                    .foregroundColor(item.status == "awaiting_payment" || item.status == "error" ? .orange : .secondary)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
}
