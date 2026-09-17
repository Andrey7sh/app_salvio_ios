import Foundation
import Network
import UIKit

/// Отправка записей: start → чанки через фоновую URLSession → finish (тот же протокол, что в Android).
/// Всё состояние живёт на main queue: delegateQueue = .main, API-вызовы через Task { @MainActor }.
final class Uploader: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = Uploader()
    static let sessionIdentifier = "io.salvio.app.upload"

    /// Неотправленные записи для списка встреч.
    @Published private(set) var recordings: [Recording] = []
    /// Запись дошла до сервера: список встреч перезагружается.
    @Published private(set) var completedCount = 0

    let store = RecordingStore()
    /// completionHandler из AppDelegate, когда система будит приложение ради фоновой сессии.
    var backgroundCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private var inFlight: [String: Set<Int>] = [:]
    private var responses: [Int: Data] = [:]
    private var apiBusy: Set<String> = []
    private var restored = false
    private var retryScheduled = false
    private var retryDelay: TimeInterval = 15
    private let monitor = NWPathMonitor()

    /// Вызывается один раз при запуске: подхватывает задачи, пережившие убийство приложения.
    func activate(activeRecordingId: String?) {
        store.recoverInterrupted(activeId: activeRecordingId)
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { self?.kick() }
        }
        monitor.start(queue: .main)
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                for task in tasks {
                    guard let key = Self.parseDescription(task.taskDescription) else { continue }
                    self.inFlight[key.id, default: []].insert(key.index)
                }
                self.restored = true
                self.kick()
            }
        }
    }

    /// Пройти по всем записям и запустить то, что можно отправить сейчас.
    func kick() {
        recordings = store.all()
        guard restored, TokenStore.access != nil else { return }
        for rec in recordings {
            for step in rec.nextSteps(inFlight: inFlight[rec.id] ?? []) {
                switch step {
                case .startCall: startCall(rec)
                case .upload(let index): upload(rec, index)
                case .finish: finish(rec)
                case .discard: store.delete(rec.id)
                }
            }
        }
        recordings = store.all()
    }

    /// Выход из аккаунта: чужие записи под новым токеном отправлять нельзя.
    func discardAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        inFlight = [:]
        store.deleteAll()
        recordings = []
    }

    // MARK: - Шаги

    private func startCall(_ rec: Recording) {
        guard apiBusy.insert(rec.id).inserted else { return }
        runInBackground {
            defer { self.apiBusy.remove(rec.id) }
            do {
                let iso = ISO8601DateFormatter().string(from: rec.startedAt)
                let response: StartCallResponse = try await APIClient.shared.send("POST", "mobile/calls/start",
                    body: .form([("title", rec.title), ("duration_seconds", "0"), ("started_at", iso)]))
                self.store.update(rec.id) { $0.serverId = response.id; $0.uploaded = [] }
                self.succeeded()
            } catch {
                self.scheduleRetry()
            }
        }
    }

    private func upload(_ rec: Recording, _ index: Int) {
        guard let serverId = rec.serverId, let token = TokenStore.access else { return }
        let boundary = "salvio-\(UUID().uuidString)"
        let bodyURL = store.bodyURL(rec.id, index)
        do {
            try RecordingStore.writeMultipart(chunk: store.chunkURL(rec.id, index), index: index, boundary: boundary, to: bodyURL)
        } catch {
            // ponytail: пропавший с диска чанк не чиним, запись повиснет в «Ожидает отправки»; при жалобах добавить сброс записи.
            scheduleRetry()
            return
        }
        var request = APIClient.makeRequest("POST", "mobile/calls/\(serverId)/chunk", body: nil, token: token)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: bodyURL)
        task.taskDescription = "\(rec.id)|\(serverId)|\(index)"
        inFlight[rec.id, default: []].insert(index)
        task.resume()
    }

    private func finish(_ rec: Recording) {
        guard let serverId = rec.serverId, apiBusy.insert(rec.id).inserted else { return }
        runInBackground {
            defer { self.apiBusy.remove(rec.id) }
            do {
                let _: StatusResponse = try await APIClient.shared.send("POST", "mobile/calls/\(serverId)/finish",
                    body: .form([("total_chunks", "\(rec.chunkCount)"), ("duration_seconds", "\(Int(rec.recordedSeconds.rounded()))")]))
                self.complete(rec.id)
            } catch let error as APIError {
                switch UploadFailure(error) {
                case .callLost:
                    self.store.update(rec.id) { $0.resetServerCall() }
                    self.kick()
                case .wrongStatus:
                    // finish отказывает только статусам после загрузки: запись уже на сервере.
                    self.complete(rec.id)
                case .chunksMismatch(let got):
                    self.store.update(rec.id) { r in r.uploaded = Set(got).intersection(0..<r.chunkCount) }
                    self.kick()
                case .unauthorized, .retry:
                    self.scheduleRetry()
                }
            } catch {
                self.scheduleRetry()
            }
        }
    }

    /// Чанк отклонён с invalid_status: либо запись уже обработана, либо звонок на сервере в error.
    private func checkServerStatus(_ id: String, serverId: String) {
        guard apiBusy.insert(id).inserted else { return }
        runInBackground {
            defer { self.apiBusy.remove(id) }
            do {
                let detail: CallDetail = try await APIClient.shared.send("GET", "calls/\(serverId)")
                if Recording.pastUpload.contains(detail.status ?? "") {
                    self.complete(id)
                } else {
                    self.store.update(id) { $0.resetServerCall() }
                    self.kick()
                }
            } catch {
                self.scheduleRetry()
            }
        }
    }

    private func complete(_ id: String) {
        store.delete(id)
        completedCount += 1
        succeeded()
    }

    private func succeeded() {
        retryDelay = 15
        kick()
    }

    private func scheduleRetry() {
        recordings = store.all()
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
            self.retryScheduled = false
            self.kick()
        }
        retryDelay = min(retryDelay * 2, 300)
    }

    /// Даём запросу дожить, если пользователь свернул приложение.
    private func runInBackground(_ work: @escaping () async -> Void) {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "salvio.upload")
        Task { @MainActor in
            await work()
            if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responses[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let data = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard let key = Self.parseDescription(task.taskDescription) else { return }
        inFlight[key.id]?.remove(key.index)
        try? FileManager.default.removeItem(at: store.bodyURL(key.id, key.index))

        // Ответ на уже сброшенный звонок (сервер его потерял) игнорируем.
        guard let rec = store.load(key.id), rec.serverId == key.serverId else { return kick() }
        let status = error == nil ? (task.response as? HTTPURLResponse)?.statusCode ?? 0 : 0
        if (200..<300).contains(status) {
            store.update(key.id) { $0.uploaded.insert(key.index) }
            return succeeded()
        }
        switch UploadFailure(APIError.parse(status: status, data: data)) {
        case .unauthorized:
            runInBackground {
                do { try await APIClient.shared.refreshTokens(); self.kick() } catch { self.scheduleRetry() }
            }
        case .callLost:
            store.update(key.id) { $0.resetServerCall() }
            kick()
        case .wrongStatus:
            checkServerStatus(key.id, serverId: key.serverId)
        case .chunksMismatch, .retry:
            scheduleRetry()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletion?()
        backgroundCompletion = nil
    }

    static func parseDescription(_ text: String?) -> (id: String, serverId: String, index: Int)? {
        guard let parts = text?.split(separator: "|").map(String.init), parts.count == 3, let index = Int(parts[2]) else { return nil }
        return (parts[0], parts[1], index)
    }
}
