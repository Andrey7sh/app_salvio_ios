import AVFoundation
import UIKit

/// Диктофон: AVAudioRecorder пишет чанки AAC в ADTS (.aac) по 5 минут.
/// ADTS выбран намеренно: у m4a индекс пишется при закрытии файла, и при убийстве приложения
/// весь текущий чанк терялся бы. ADTS-поток читается до последнего записанного кадра.
final class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = Recorder()
    static let chunkSeconds: TimeInterval = 5 * 60
    static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    @Published private(set) var recordingId: String?
    @Published private(set) var elapsed: TimeInterval = 0
    /// Звонок, Siri или другое приложение забрали микрофон, чанк закрыт, ждём возврата.
    @Published private(set) var isInterrupted = false
    @Published var errorMessage: String?

    var isRecording: Bool { recordingId != nil }

    private var recorder: AVAudioRecorder?
    private var closedSeconds: TimeInterval = 0
    private var timer: Timer?
    private var store: RecordingStore { Uploader.shared.store }

    override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleMediaReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    func start() async {
        guard !isRecording else { return }
        let granted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        await MainActor.run {
            guard granted else {
                errorMessage = "Нет разрешения на микрофон. Включите его в Настройках iPhone: Salvio → Микрофон."
                return
            }
            begin()
        }
    }

    private func begin() {
        guard activateSession() else {
            errorMessage = "Не удалось начать запись"
            return
        }
        let rec = Recording.new()
        store.save(rec)
        recordingId = rec.id
        closedSeconds = 0
        elapsed = 0
        errorMessage = nil
        guard openChunk() else {
            stop()
            errorMessage = "Не удалось начать запись"
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        guard let id = recordingId else { return }
        closeChunk()
        timer?.invalidate()
        timer = nil
        store.update(id) { $0.isFinished = true }
        recordingId = nil
        isInterrupted = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Uploader.shared.kick()
    }

    /// Кнопка «Продолжить» и конец прерывания.
    func resume() {
        guard isRecording, recorder == nil else { return }
        isInterrupted = !(activateSession() && openChunk())
        if isInterrupted { errorMessage = "Микрофон занят другим приложением. Нажмите «Продолжить» позже." }
    }

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.allowBluetooth])
            // Уведомления и входящие системные алерты не должны рвать запись.
            try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func openChunk() -> Bool {
        guard let id = recordingId, let rec = store.load(id) else { return false }
        let index = rec.chunkCount
        guard let r = try? AVAudioRecorder(url: store.chunkURL(id, index), settings: Self.settings), r.record() else {
            return false
        }
        r.delegate = self
        recorder = r
        store.update(id) { $0.chunkCount = index + 1; $0.openChunk = index }
        isInterrupted = false
        errorMessage = nil
        return true
    }

    /// Закрывает текущий чанк: файл дописан и уходит в загрузку.
    private func closeChunk() {
        guard let id = recordingId, let r = recorder else { return }
        closedSeconds += r.currentTime
        recorder = nil
        r.delegate = nil
        r.stop()
        store.update(id) { $0.openChunk = nil; $0.recordedSeconds = self.closedSeconds }
        store.dropEmptyLastChunk(id)
        Uploader.shared.kick()
    }

    private func tick() {
        guard isRecording else { return }
        let current = recorder?.currentTime ?? 0
        elapsed = closedSeconds + current
        if current >= Self.chunkSeconds {
            closeChunk()
            if !openChunk() { isInterrupted = true }
        }
    }

    // MARK: - Прерывания

    @objc private func handleInterruption(_ note: Notification) {
        guard isRecording,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async {
            switch type {
            case .began:
                self.closeChunk()
                self.isInterrupted = true
            case .ended:
                // Возобновляем всегда: после звонка iOS не всегда присылает shouldResume, а запись встречи должна идти дальше.
                self.resume()
            @unknown default:
                break
            }
        }
    }

    @objc private func handleMediaReset() {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            // Старый AVAudioRecorder после сброса медиасервисов мёртв, открываем новый чанк.
            self.closeChunk()
            self.resume()
        }
    }

    @objc private func handleTerminate() {
        stop()
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.closeChunk()
            self.resume()
        }
    }
}
