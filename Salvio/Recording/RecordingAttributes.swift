import ActivityKit
import Foundation

/// Данные индикатора записи на экране блокировки и в Dynamic Island.
/// Файл общий для приложения и виджет-расширения.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Момент, от которого система сама тикает таймер, пока запись идёт.
        var startedAt: Date
        /// Сколько уже записано на момент паузы.
        var elapsed: TimeInterval
        var isPaused: Bool
    }

    var title: String
}
