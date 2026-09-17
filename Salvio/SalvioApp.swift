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

    var body: some Scene {
        WindowGroup {
            Text("Salvio")
        }
    }
}
