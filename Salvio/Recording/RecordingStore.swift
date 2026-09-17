import Foundation

/// Локальная запись. Папка recordings/<id>/: manifest.json, chunk_N.aac, body_N.multipart.
/// Манифест переживает убийство приложения: загрузчик доотправит чанки при следующем запуске.
struct Recording: Codable, Equatable, Identifiable {
    var id: String
    var serverId: String?
    var title: String
    var startedAt: Date
    var recordedSeconds: Double = 0
    /// Чанки 0..<chunkCount лежат на диске.
    var chunkCount = 0
    /// Индекс чанка, который диктофон пишет прямо сейчас. Его не грузим.
    var openChunk: Int?
    /// Пользователь остановил запись (или её восстановили после падения). Только тогда вызываем finish.
    var isFinished = false
    var uploaded: Set<Int> = []

    static func new(now: Date = Date()) -> Recording {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return Recording(id: UUID().uuidString, title: "Встреча \(f.string(from: now))", startedAt: now)
    }

    enum Step: Equatable {
        case startCall
        case upload(Int)
        case finish
        /// Запись без аудио: удалить локально, на сервер нечего слать.
        case discard
    }

    /// Что делать загрузчику с записью. inFlight: чанки, уже отданные фоновой URLSession.
    func nextSteps(inFlight: Set<Int>) -> [Step] {
        let closed = (0..<chunkCount).filter { $0 != openChunk }
        if closed.isEmpty { return isFinished && chunkCount == 0 ? [.discard] : [] }
        guard serverId != nil else { return [.startCall] }
        let pending = closed.filter { !uploaded.contains($0) && !inFlight.contains($0) }
        if !pending.isEmpty { return pending.map { .upload($0) } }
        let allUploaded = (0..<chunkCount).allSatisfy { uploaded.contains($0) }
        return isFinished && allUploaded ? [.finish] : []
    }

    /// Сервер потерял звонок (404/403): заводим новый и шлём все чанки заново.
    mutating func resetServerCall() {
        serverId = nil
        uploaded = []
    }

    /// Статусы, после которых сервер чанки уже не принимает: запись дошла.
    static let pastUpload: Set<String> = ["uploaded", "transcribing", "transcribed", "analyzing", "done", "awaiting_payment"]
}

/// Как реагировать на ошибку загрузки чанка или finish.
enum UploadFailure: Equatable {
    case unauthorized
    case callLost
    case wrongStatus
    /// invalid_chunks: сервер прислал, какие индексы у него есть.
    case chunksMismatch(got: [Int])
    case retry

    init(_ error: APIError) {
        switch (error.status, error.code) {
        case (401, _): self = .unauthorized
        case (403, _), (404, _): self = .callLost
        case (400, "invalid_status"?): self = .wrongStatus
        case (400, "invalid_chunks"?):
            var got: [Int] = []
            if case .array(let list)? = error.details?["got"] {
                got = list.compactMap { if case .number(let n) = $0 { return Int(n) } else { return nil } }
            }
            self = .chunksMismatch(got: got)
        default: self = .retry
        }
    }
}

final class RecordingStore {
    let root: URL
    /// Меньше этого в чанке нет ни одного аудиокадра (пустой чанк после мгновенного прерывания).
    static let minChunkBytes = 256

    init(root: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = root ?? base.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        self.root = dir
    }

    func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func chunkURL(_ id: String, _ index: Int) -> URL { dir(id).appendingPathComponent("chunk_\(index).aac") }
    func bodyURL(_ id: String, _ index: Int) -> URL { dir(id).appendingPathComponent("body_\(index).multipart") }
    private func manifestURL(_ id: String) -> URL { dir(id).appendingPathComponent("manifest.json") }

    func save(_ rec: Recording) {
        try? FileManager.default.createDirectory(at: dir(rec.id), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(rec) {
            try? data.write(to: manifestURL(rec.id), options: .atomic)
        }
    }

    func load(_ id: String) -> Recording? {
        guard let data = try? Data(contentsOf: manifestURL(id)) else { return nil }
        return try? JSONDecoder().decode(Recording.self, from: data)
    }

    /// Читает свежий манифест с диска, чтобы диктофон и загрузчик не затирали изменения друг друга.
    @discardableResult
    func update(_ id: String, _ change: (inout Recording) -> Void) -> Recording? {
        guard var rec = load(id) else { return nil }
        change(&rec)
        save(rec)
        return rec
    }

    func all() -> [Recording] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap(load).sorted { $0.startedAt > $1.startedAt }
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: dir(id))
    }

    func deleteAll() {
        for rec in all() { delete(rec.id) }
    }

    /// Последний чанк без аудио удаляем, чтобы сервер не получил пустой файл (ffmpeg на нём падает).
    func dropEmptyLastChunk(_ id: String) {
        update(id) { rec in
            guard rec.chunkCount > 0, rec.openChunk != rec.chunkCount - 1 else { return }
            let url = chunkURL(id, rec.chunkCount - 1)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if size < Self.minChunkBytes {
                try? FileManager.default.removeItem(at: url)
                rec.chunkCount -= 1
                rec.uploaded.remove(rec.chunkCount)
            }
        }
    }

    /// После убийства приложения посреди записи: чанк ADTS читается до последнего целого кадра,
    /// поэтому закрываем запись с тем, что успело лечь на диск.
    func recoverInterrupted(activeId: String?) {
        for rec in all() where !rec.isFinished && rec.id != activeId {
            update(rec.id) { $0.openChunk = nil; $0.isFinished = true }
            dropEmptyLastChunk(rec.id)
        }
    }

    /// multipart/form-data для POST /mobile/calls/{id}/chunk, пишется в файл:
    /// фоновая URLSession умеет грузить только из файла.
    static func writeMultipart(chunk: URL, index: Int, boundary: String, to dest: URL) throws {
        let audio = try Data(contentsOf: chunk, options: .mappedIfSafe)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"chunk_index\"\r\n\r\n\(index)\r\n".utf8))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk_\(index).aac\"\r\nContent-Type: audio/aac\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        try body.write(to: dest, options: .atomic)
    }
}
