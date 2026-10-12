import AVFoundation
import SwiftUI

/// Плеер записи: общий для полосы с кнопкой и транскрипта (клик по реплике перематывает, текущая подсвечена).
@MainActor
final class PlayerModel: ObservableObject {
    let url: URL
    /// Длительность с сервера: у presigned-ссылки AVPlayer узнаёт её не сразу.
    let fallbackDuration: Double

    @Published private(set) var playing = false
    @Published var position: Double = 0
    @Published private(set) var duration: Double = 0
    var scrubbing = false

    private var player: AVPlayer?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL, fallbackDuration: Double) {
        self.url = url
        self.fallbackDuration = fallbackDuration
    }

    var total: Double { duration > 0 ? duration : fallbackDuration }
    /// Позиция для подсветки реплики: только когда запись слушают или ставили на паузу не в начале.
    var currentMs: Int? { playing || position > 0 ? Int(position * 1000) : nil }

    func toggle() { playing ? pause() : play() }

    func play() {
        let player = prepared()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        playing = true
    }

    func pause() {
        player?.pause()
        playing = false
    }

    func seek(to seconds: Double) {
        position = seconds
        prepared().seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Реплика транскрипта: перемотать и сразу слушать.
    func play(fromMs ms: Int) {
        seek(to: Double(ms) / 1000)
        play()
    }

    func teardown() {
        if let observer { player?.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil
        endObserver = nil
        player?.pause()
        player = nil
        playing = false
    }

    private func prepared() -> AVPlayer {
        if let player { return player }
        let new = AVPlayer(url: url)
        observer = new.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                if let item = new.currentItem, item.duration.isNumeric { self.duration = item.duration.seconds }
                if !self.scrubbing { self.position = time.seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: new.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.playing = false
                self?.position = 0
                new.seek(to: .zero)
            }
        }
        player = new
        return new
    }
}

/// Полоса плеера, как в Android: кнопка, прогресс и время.
struct AudioPlayerView: View {
    @ObservedObject var player: PlayerModel
    @ObservedObject private var recorder = Recorder.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .accessibilityLabel(player.playing ? "Пауза" : "Слушать запись")

                VStack(spacing: 2) {
                    Slider(value: $player.position, in: 0...max(player.total, 1)) { editing in
                        player.scrubbing = editing
                        if !editing { player.seek(to: player.position) }
                    }
                    HStack {
                        Text(Format.duration(player.position))
                        Spacer()
                        Text(Format.duration(player.total))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                }
            }
            if recorder.isRecording {
                Text("Прослушивание недоступно во время записи").font(.caption).foregroundColor(.secondary)
            }
        }
        // Смена категории аудиосессии на воспроизведение оборвала бы идущую запись.
        .disabled(recorder.isRecording)
    }
}
