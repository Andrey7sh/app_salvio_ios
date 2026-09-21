import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Uploader.shared.activate(activeRecordingId: Recorder.shared.recordingId)
        return true
    }

    /// Система разбудила приложение, чтобы доставить результаты фоновых загрузок.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Uploader.sessionIdentifier else { return completionHandler() }
        Uploader.shared.backgroundCompletion = completionHandler
    }
}

@main
struct SalvioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject private var recorder = Recorder.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        Group {
            if session.isLoggedIn {
                VStack(spacing: 0) {
                    // Плашка видна на любой вкладке: пользователь не теряет из виду, что запись идёт.
                    if recorder.isRecording {
                        Button { tab = 0 } label: { RecordingBanner(recorder: recorder) }
                            .buttonStyle(.plain)
                    }
                    TabView(selection: $tab) {
                        RecordView().tabItem { Label("Запись", systemImage: "mic.circle") }.tag(0)
                        CallsListView().tabItem { Label("Встречи", systemImage: "list.bullet") }.tag(1)
                        ProfileView().tabItem { Label("Профиль", systemImage: "person.crop.circle") }.tag(2)
                    }
                }
            } else {
                AuthView()
            }
        }
        .animation(.default, value: recorder.isRecording)
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Uploader.shared.kick()
            Task { await session.refresh() }
        }
    }
}

/// Красная полоса «Идёт запись» над вкладками.
private struct RecordingBanner: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: recorder.isCapturing ? "waveform" : "pause.fill")
                .symbolRenderingMode(.hierarchical)
            Text(recorder.isCapturing ? "Идёт запись" : "Запись на паузе")
                .bold()
            Spacer()
            Text(Format.duration(recorder.elapsed)).monospacedDigit()
        }
        .font(.footnote)
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(recorder.isCapturing ? Color.red : Color.orange)
    }
}
