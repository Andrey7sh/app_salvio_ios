import SwiftUI

/// Журнал приложения: видно, почему запись встала на паузу и что ответил сервер на загрузку.
struct DiagnosticsView: View {
    @State private var lines: [String] = []
    @State private var exported: URL?

    var body: some View {
        List {
            Section {
                if let exported {
                    ShareLink(item: exported) {
                        Label("Отправить журнал в поддержку", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Обновить") { reload() }
                Button("Очистить журнал", role: .destructive) {
                    RecordingLog.shared.clear()
                    reload()
                }
            } footer: {
                Text("В журнале только события приложения: старт и пауза записи, номера кусков, коды ответов сервера. Текстов встреч и паролей в нём нет.")
            }
            Section("Последние события") {
                if lines.isEmpty {
                    Text("Пока пусто").foregroundColor(.secondary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        lines = RecordingLog.shared.tail()
        exported = RecordingLog.shared.exportFile()
    }
}
