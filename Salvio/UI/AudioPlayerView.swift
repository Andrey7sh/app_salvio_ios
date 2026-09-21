import AVFoundation
import SwiftUI

/// Плеер записи с перемоткой, как в Android: кнопка, полоса прогресса и время.
struct AudioPlayerView: View {
    let url: URL
    /// Длительность с сервера: у presigned-ссылки AVPlayer узнаёт её не сразу.
    let fallbackDuration: Double

    @ObservedObject private var recorder = Recorder.shared
    @State private var player: AVPlayer?
    @State private var observer: Any?
    @State private var playing = false
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var scrubbing = false

    private var total: Double { duration > 0 ? duration : fallbackDuration }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    playing ? pause() : play()
                } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .accessibilityLabel(playing ? "Пауза" : "Слушать запись")

                VStack(spacing: 2) {
                    Slider(value: $position, in: 0...max(total, 1)) { editing in
                        scrubbing = editing
                        if !editing { seek(to: position) }
                    }
                    HStack {
                        Text(Format.duration(position))
                        Spacer()
                        Text(Format.duration(total))
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
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            playing = false
            position = 0
            player?.seek(to: .zero)
        }
        .onDisappear(perform: teardown)
    }

    private func play() {
        let player = preparedPlayer()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        playing = true
    }

    private func pause() {
        player?.pause()
        playing = false
    }

    private func seek(to seconds: Double) {
        preparedPlayer().seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func preparedPlayer() -> AVPlayer {
        if let player { return player }
        let new = AVPlayer(url: url)
        observer = new.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            if let item = new.currentItem, item.duration.isNumeric {
                duration = item.duration.seconds
            }
            guard !scrubbing else { return }
            position = time.seconds
        }
        player = new
        return new
    }

    private func teardown() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        playing = false
    }
}
