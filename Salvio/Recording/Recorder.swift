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
    /// Сколько раз пробуем вернуть микрофон после прерывания, прежде чем сдаться и ждать пользователя.
    private static let resumeAttempts = 15
    private static let resumeDelay: TimeInterval = 2

    @Published private(set) var recordingId: String?
    @Published private(set) var elapsed: TimeInterval = 0
    /// Пользователь нажал «Пауза».
    @Published private(set) var isPausedByUser = false
    /// Звонок, Siri или другое приложение забрали микрофон. Возобновляем сами.
    @Published private(set) var isInterrupted = false
    @Published var errorMessage: String?

    var isRecording: Bool { recordingId != nil }
    var isCapturing: Bool { recorder != nil }

    private var recorder: AVAudioRecorder?
    private var closedSeconds: TimeInterval = 0
    private var timer: Timer?
    private var resumeTimer: Timer?
    private var resumeTries = 0
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
                log("mic", "пользователь не дал доступ к микрофону")
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
        isPausedByUser = false
        errorMessage = nil
        log("rec", "старт записи \(rec.id)")
        guard openChunk() else {
            stop()
            errorMessage = "Не удалось начать запись"
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RecordingActivityController.start(title: rec.title)
    }

    func stop() {
        guard let id = recordingId else { return }
        closeChunk()
        timer?.invalidate()
        timer = nil
        cancelResumeRetries()
        store.update(id) { $0.isFinished = true }
        let seconds = closedSeconds
        recordingId = nil
        isInterrupted = false
        isPausedByUser = false
        elapsed = 0
        closedSeconds = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        RecordingActivityController.stop()
        log("rec", "стоп записи \(id), длительность \(Int(seconds)) с")
        Uploader.shared.kick()
    }

    /// Пауза по кнопке: текущий чанк закрывается и сразу уходит на сервер.
    func pause() {
        guard isRecording, isCapturing else { return }
        closeChunk()
        isPausedByUser = true
        cancelResumeRetries()
        log("rec", "пауза по кнопке на \(Int(closedSeconds)) с")
        RecordingActivityController.update(elapsed: elapsed, isPaused: true)
    }

    /// Кнопка «Продолжить» и автоматическое возобновление после прерывания.
    func resume() {
        guard isRecording, !isCapturing else { return }
        cancelResumeRetries()
        guard activateSession(), openChunk() else {
            log("rec", "возобновить не удалось, микрофон занят")
            isInterrupted = true
            scheduleResumeRetry()
            return
        }
        isPausedByUser = false
        isInterrupted = false
        errorMessage = nil
        log("rec", "запись возобновлена")
        RecordingActivityController.update(elapsed: elapsed, isPaused: false)
    }

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord + mixWithOthers: звук уведомлений и чужая музыка не прерывают запись.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            do {
                try session.setPrefersNoInterruptionsFromSystemAlerts(true)
            } catch {
                log("audio", "системные алерты могут прерывать запись: \(error.localizedDescription)")
            }
            try session.setActive(true)
            return true
        } catch {
            log("audio", "не удалось включить аудиосессию: \(error.localizedDescription)")
            return false
        }
    }

    private func openChunk() -> Bool {
        guard let id = recordingId, let rec = store.load(id) else { return false }
        let index = rec.chunkCount
        guard let r = try? AVAudioRecorder(url: store.chunkURL(id, index), settings: Self.settings), r.record() else {
            log("rec", "не удалось открыть чанк \(index)")
            return false
        }
        r.delegate = self
        recorder = r
        store.update(id) { $0.chunkCount = index + 1; $0.openChunk = index }
        log("rec", "пишем чанк \(index)")
        return true
    }

    /// Закрывает текущий чанк: файл дописан и уходит в загрузку.
    private func closeChunk() {
        guard let id = recordingId, let r = recorder else { return }
        let seconds = r.currentTime
        closedSeconds += seconds
        recorder = nil
        r.delegate = nil
        r.stop()
        store.update(id) { $0.openChunk = nil; $0.recordedSeconds = self.closedSeconds }
        store.dropEmptyLastChunk(id)
        elapsed = closedSeconds
        log("rec", "чанк закрыт, \(Int(seconds)) с, всего \(Int(closedSeconds)) с")
        Uploader.shared.kick()
    }

    private func tick() {
        guard isRecording else { return }
        let current = recorder?.currentTime ?? 0
        elapsed = closedSeconds + current
        if current >= Self.chunkSeconds {
            closeChunk()
            if openChunk() {
                RecordingActivityController.update(elapsed: elapsed, isPaused: false)
            } else {
                isInterrupted = true
                scheduleResumeRetry()
            }
        }
    }

    // MARK: - Прерывания

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let reason = (note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).map { "reason \($0)" } ?? ""
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            switch type {
            case .began:
                self.log("audio", "прерывание началось \(reason)")
                guard !self.isPausedByUser else { return }
                self.closeChunk()
                self.isInterrupted = true
                RecordingActivityController.update(elapsed: self.elapsed, isPaused: true)
                // Иногда .ended не приходит (например, звонок завершили из другого приложения),
                // поэтому пробуем вернуть микрофон сами.
                self.scheduleResumeRetry()
            case .ended:
                self.log("audio", "прерывание закончилось")
                guard !self.isPausedByUser else { return }
                self.resume()
            @unknown default:
                break
            }
        }
    }

    private func scheduleResumeRetry() {
        guard isRecording, !isPausedByUser, resumeTimer == nil else { return }
        resumeTries = 0
        resumeTimer = Timer.scheduledTimer(withTimeInterval: Self.resumeDelay, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isRecording, !self.isPausedByUser else { return self.cancelResumeRetries() }
            guard !self.isCapturing else { return self.cancelResumeRetries() }
            self.resumeTries += 1
            if self.resumeTries > Self.resumeAttempts {
                self.cancelResumeRetries()
                self.errorMessage = "Микрофон занят другим приложением. Нажмите «Продолжить», когда освободится."
                self.log("audio", "автовозобновление сдалось после \(Self.resumeAttempts) попыток")
                return
            }
            if self.activateSession(), self.openChunk() {
                self.isInterrupted = false
                self.errorMessage = nil
                self.log("audio", "микрофон вернулся с попытки \(self.resumeTries)")
                RecordingActivityController.update(elapsed: self.elapsed, isPaused: false)
                self.cancelResumeRetries()
            }
        }
    }

    private func cancelResumeRetries() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        resumeTries = 0
    }

    @objc private func handleMediaReset() {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            // Старый AVAudioRecorder после сброса медиасервисов мёртв, открываем новый чанк.
            self.log("audio", "сброс медиасервисов")
            self.recorder = nil
            self.store.update(self.recordingId ?? "") { $0.openChunk = nil }
            guard !self.isPausedByUser else { return }
            self.resume()
        }
    }

    @objc private func handleTerminate() {
        log("rec", "приложение выгружается, закрываем запись")
        stop()
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.log("rec", "ошибка кодирования: \(error?.localizedDescription ?? "без описания")")
            self.closeChunk()
            guard !self.isPausedByUser else { return }
            self.resume()
        }
    }

    private func log(_ tag: String, _ message: String) {
        appLog(tag, message)
    }
}
