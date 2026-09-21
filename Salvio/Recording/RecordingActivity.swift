import ActivityKit
import Foundation

/// Индикатор записи на экране блокировки и в Dynamic Island.
/// Всё завёрнуто в проверки: пользователь может выключить Live Activity в настройках iPhone,
/// и это не должно мешать записи.
enum RecordingActivityController {
    private static var activity: Activity<RecordingAttributes>?

    static func start(title: String) {
        stop()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            appLog("activity", "Live Activity выключены в настройках iPhone")
            return
        }
        let state = RecordingAttributes.ContentState(startedAt: Date(), elapsed: 0, isPaused: false)
        do {
            activity = try Activity.request(
                attributes: RecordingAttributes(title: title),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            appLog("activity", "индикатор записи запущен")
        } catch {
            appLog("activity", "не удалось запустить индикатор: \(error.localizedDescription)")
        }
    }

    static func update(elapsed: TimeInterval, isPaused: Bool) {
        guard let activity else { return }
        let state = RecordingAttributes.ContentState(startedAt: Date().addingTimeInterval(-elapsed), elapsed: elapsed, isPaused: isPaused)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func stop() {
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}
