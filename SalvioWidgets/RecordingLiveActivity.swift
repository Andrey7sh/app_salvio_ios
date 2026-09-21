import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SalvioWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

/// Плашка «Идёт запись» на экране блокировки и в Dynamic Island.
/// Таймер система тикает сама из startedAt, поэтому обновлять активность каждую секунду не нужно.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "waveform.circle.fill")
                    .font(.title)
                    .foregroundColor(context.state.isPaused ? .orange : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isPaused ? "Запись на паузе" : "Идёт запись")
                        .font(.headline)
                    Text(context.attributes.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                timer(context.state).font(.title3.monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "waveform.circle.fill")
                        .font(.title2)
                        .foregroundColor(context.state.isPaused ? .orange : .red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isPaused ? "Запись на паузе" : context.attributes.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundColor(context.state.isPaused ? .orange : .red)
            } compactTrailing: {
                timer(context.state).font(.caption2.monospacedDigit()).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundColor(context.state.isPaused ? .orange : .red)
            }
        }
    }

    @ViewBuilder
    private func timer(_ state: RecordingAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(Self.paused(state.elapsed))
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
        }
    }

    private static func paused(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%02d:%02d", s / 60, s % 60)
    }
}
