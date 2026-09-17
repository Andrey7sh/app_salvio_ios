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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.isLoggedIn {
                TabView {
                    RecordView().tabItem { Label("Запись", systemImage: "mic.circle") }
                    CallsListView().tabItem { Label("Встречи", systemImage: "list.bullet") }
                    ProfileView().tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                }
            } else {
                AuthView()
            }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Uploader.shared.kick()
            Task { await session.refresh() }
        }
    }
}
