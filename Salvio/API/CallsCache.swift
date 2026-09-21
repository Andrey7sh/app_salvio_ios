import Foundation

/// Последний загруженный список встреч на диске: без сети экран не остаётся пустым, как в Android.
/// Храним только то, что и так видно в списке: id, название, дату, длительность и статус.
enum CallsCache {
    static let limit = 50

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calls-cache.json")
    }

    static func save(_ items: [CallItem]) {
        guard let data = try? JSONEncoder().encode(Array(items.prefix(limit))) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> [CallItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([CallItem].self, from: data) else { return [] }
        return items
    }

    /// Выход из аккаунта и удаление аккаунта: чужие встречи на экране показывать нельзя.
    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
