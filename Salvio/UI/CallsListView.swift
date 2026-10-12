import SwiftUI

@MainActor
final class CallsModel: ObservableObject {
    static let unfiled = "unfiled"
    static let trash = "trash"

    @Published private(set) var items: [CallItem] = []
    @Published private(set) var loaded = false
    /// Список взят из кэша: сервер недоступен.
    @Published private(set) var offline = false
    @Published var error: String?
    @Published var notice: String?

    /// Поиск и папки идут на сервер мимо офлайн-кэша: кэш хранит только последние записи без папок.
    @Published var query = ""
    @Published private(set) var folder: String?
    @Published private(set) var folders: FoldersResponse?
    private var page = 0
    private var totalPages = 1
    private var loading = false
    private var generation = 0
    /// Пространство, для которого показан список: .task перезапускается при возврате с экрана встречи,
    /// а папку и поиск при этом сбрасывать нельзя.
    private var shownWorkspace: String?? = nil
    private var lastQuery = ""

    var filtered: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty || folder != nil }
    var inTrash: Bool { folder == Self.trash }
    var ownFolder: Folder? { folders?.folders.first { $0.id == folder } }
    var folderTitle: String? {
        switch folder {
        case nil: return nil
        case Self.unfiled?: return "Без папки"
        case Self.trash?: return "Корзина"
        default: return ownFolder?.name ?? "Папка"
        }
    }

    func reload() async {
        page = 0
        totalPages = 1
        generation += 1
        await loadMore(reset: true)
    }

    func loadMore(reset: Bool = false) async {
        guard !loading || reset, page < totalPages else { return }
        loading = true
        let gen = generation
        defer { if gen == generation { loading = false } }
        let q = query.trimmingCharacters(in: .whitespaces)
        do {
            let result: CallsPage = filtered
                ? try await MeetingAPI.search(q: q, folder: folder ?? "all", page: page + 1)
                : try await APIClient.shared.send("GET", "calls?page=\(page + 1)&limit=20")
            // Пока шёл запрос, поменяли поиск или папку: ответ устарел.
            guard gen == generation else { return }
            items = reset ? result.items : items + result.items.filter { new in !items.contains { $0.id == new.id } }
            page = result.page
            totalPages = result.totalPages
            error = nil
            offline = false
            if page == 1, !filtered { CallsCache.save(items) }
        } catch {
            guard gen == generation else { return }
            let cached = CallsCache.load()
            if reset, !filtered, !cached.isEmpty {
                items = cached
                offline = true
                self.error = nil
            } else {
                self.error = error.localizedDescription
            }
        }
        loaded = true
    }

    func loadFolders() async {
        if let f = try? await MeetingAPI.folders() { folders = f }
    }

    func enter(workspace: String?) async {
        guard shownWorkspace != .some(workspace) else { return }
        shownWorkspace = .some(workspace)
        // Папки у каждого пространства свои: выбранная в прошлом пространстве здесь не существует.
        await open(folder: nil)
        await loadFolders()
    }

    /// Поиск после паузы в наборе; тот же текст повторно список не перечитывает.
    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q != lastQuery else { return }
        lastQuery = q
        await reload()
    }

    func open(folder: String?) async {
        self.folder = folder
        await reload()
    }

    func restore(_ item: CallItem) async { await mutate("Запись восстановлена") { try await MeetingAPI.restore(item.id) } }
    func purge(_ item: CallItem) async { await mutate("Запись удалена навсегда") { try await MeetingAPI.purge(item.id) } }
    func createFolder(_ name: String) async {
        await mutate("Папка создана") { _ = try await MeetingAPI.createFolder(String(name.prefix(120))) }
    }
    func renameFolder(_ name: String) async {
        guard let id = ownFolder?.id else { return }
        await mutate("Папка переименована") { _ = try await MeetingAPI.renameFolder(id, String(name.prefix(120))) }
    }

    /// Записи удалённой папки остаются «Без папки» (так работает сервер), поэтому показываем их там.
    func deleteFolder() async {
        guard let id = ownFolder?.id else { return }
        do {
            try await MeetingAPI.deleteFolder(id)
            notice = "Папка удалена, записи перенесены в «Без папки»"
            await loadFolders()
            await open(folder: Self.unfiled)
        } catch {
            notice = error.localizedDescription
        }
    }

    private func mutate(_ success: String, _ action: () async throws -> Void) async {
        do {
            try await action()
            notice = success
            await loadFolders()
            await reload()
        } catch {
            notice = error.localizedDescription
        }
    }
}

struct CallsListView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = CallsModel()
    @ObservedObject private var uploader = Uploader.shared
    @State private var trashItem: CallItem?
    @State private var naming: FolderNaming?
    @State private var folderName = ""

    enum FolderNaming { case create, rename }

    // Тело разбито на части: одной цепочкой модификаторов компилятор не успевал вывести типы.
    var body: some View {
        NavigationStack {
            dialogs
        }
    }

    private var list: some View {
        List {
            if !uploader.recordings.isEmpty, !model.filtered {
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
                    Group {
                        if model.inTrash {
                            Button { trashItem = item } label: { CallRow(item: item) }.buttonStyle(.plain)
                        } else {
                            NavigationLink(value: item) { CallRow(item: item) }
                        }
                    }
                    .onAppear {
                        if item.id == model.items.last?.id { Task { await model.loadMore() } }
                    }
                }
            }
        }
    }

    private var screen: some View {
        list
        .overlay { emptyState }
        .searchable(text: $model.query, prompt: "Название, слова из разговора или итогов")
        // Ждём паузу в наборе, чтобы не дёргать сервер на каждую букву.
        .task(id: model.query) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled, model.loaded { await model.search() }
        }
        .refreshable {
            uploader.kick()
            await model.loadFolders()
            await model.reload()
        }
        // Список показывает текущее пространство. Сменили его здесь или в вебе: перечитываем.
        .navigationTitle(title)
        .navigationDestination(for: CallItem.self) { CallDetailView(call: $0) }
        .toolbar { ToolbarItem(placement: .primaryAction) { foldersMenu } }
        .task(id: session.workspaces?.current) { await model.enter(workspace: session.workspaces?.current) }
        .task { await session.loadWorkspaces() }
        // Вернулись с экрана встречи: её могли удалить, перенести или переименовать.
        .onAppear { if model.loaded { Task { await model.loadFolders(); await model.reload() } } }
        .onChange(of: uploader.completedCount) { _ in Task { await model.reload() } }
    }

    private var title: String {
        if let folder = model.folderTitle { return folder }
        if let ws = session.workspaces { return "Встречи · " + ws.currentName }
        return "Встречи"
    }

    private func counted(_ name: String, _ n: Int?) -> String {
        guard let n else { return name }
        return name + " (" + String(n) + ")"
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    }

    private var trashShown: Binding<Bool> {
        Binding(get: { trashItem != nil }, set: { if !$0 { trashItem = nil } })
    }

    private var namingShown: Binding<Bool> {
        Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })
    }

    private var dialogs: some View {
        screen
        .alert(model.notice ?? "", isPresented: noticeShown) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(trashItem?.title ?? "Запись", isPresented: trashShown,
                            titleVisibility: .visible, presenting: trashItem) { item in
            Button("Восстановить") { Task { await model.restore(item) } }
            Button("Удалить навсегда", role: .destructive) { Task { await model.purge(item) } }
        } message: { _ in
            Text("Запись в корзине. Через 30 дней после удаления она сотрётся навсегда вместе с аудио.")
        }
        .alert(naming == .rename ? "Переименовать папку" : "Новая папка",
               isPresented: namingShown) {
            TextField("Название", text: $folderName)
            Button("Сохранить") {
                let name = folderName.trimmingCharacters(in: .whitespaces)
                let action = naming
                guard !name.isEmpty else { return }
                Task {
                    if action == .rename { await model.renameFolder(name) } else { await model.createFolder(name) }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var foldersMenu: some View {
        OnboardingTip(.listFolders) {
            Menu {
                Button(counted("Все встречи", model.folders?.all)) { Task { await model.open(folder: nil) } }
                Button(counted("Без папки", model.folders?.unfiled)) { Task { await model.open(folder: CallsModel.unfiled) } }
                ForEach(model.folders?.folders ?? []) { folder in
                    Button(counted(folder.name, folder.count ?? 0)) { Task { await model.open(folder: folder.id) } }
                }
                Button(counted("Корзина", model.folders?.trash)) { Task { await model.open(folder: CallsModel.trash) } }
                Divider()
                Button { folderName = ""; naming = .create } label: { Label("Новая папка", systemImage: "folder.badge.plus") }
                if let own = model.ownFolder {
                    Button { folderName = own.name; naming = .rename } label: { Label("Переименовать «\(own.name)»", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await model.deleteFolder() } } label: { Label("Удалить папку", systemImage: "trash") }
                }
            } label: {
                Image(systemName: model.folder == nil ? "folder" : "folder.fill")
            }
            .accessibilityLabel("Папки")
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.loaded, model.items.isEmpty, model.error == nil {
            if model.filtered {
                Text(!model.query.isEmpty ? "Ничего не нашлось" : model.inTrash ? "Корзина пуста" : "В папке пока нет записей")
                    .foregroundColor(.secondary)
            } else if uploader.recordings.isEmpty {
                VStack(spacing: 8) {
                    Text("Записанных встреч пока нет").font(.headline)
                    Text("Нажмите «Начать запись», чтобы создать первую встречу").foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding()
            }
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
                Text(Format.status(item.status, errorCode: item.errorCode))
                    .foregroundColor(item.status == "awaiting_payment" || item.status == "error" ? .orange : .secondary)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
}
