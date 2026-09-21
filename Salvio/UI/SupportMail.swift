import MessageUI
import SwiftUI

/// Письмо в поддержку с уже подставленными данными аккаунта и телефона, как в Android 1.4,
/// плюс журнал приложения вложением: по нему видно, что происходило с записью и загрузкой.
enum Support {
    static let address = "support@salvio.io"

    static func subject(version: String) -> String {
        "Salvio iOS \(version): обращение в поддержку"
    }

    static func body(email: String?, version: String, device: String, system: String) -> String {
        """


        ---
        Данные для поддержки, не удаляйте:
        Аккаунт: \(email?.isEmpty == false ? email! : "не определён")
        Версия приложения: \(version)
        Телефон: \(device)
        iOS: \(system)
        """
    }

    /// Модель устройства вида iPhone15,2: UIDevice отдаёт только «iPhone».
    static var deviceIdentifier: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { raw -> String in
            let pointer = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: pointer)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    /// Запасной путь, когда почта на устройстве не настроена: открыть mailto или скопировать адрес.
    @MainActor
    static func openMailtoOrCopy(email: String?) -> String {
        let version = appVersion
        let text = body(email: email, version: version, device: deviceIdentifier, system: UIDevice.current.systemVersion)
        var components = URLComponents(string: "mailto:\(address)")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject(version: version)),
            URLQueryItem(name: "body", value: text),
        ]
        if let url = components?.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return "Открываем почту"
        }
        UIPasteboard.general.string = address
        return "Почта \(address) скопирована"
    }
}

/// Системное окно письма с вложенным журналом.
struct SupportMailView: UIViewControllerRepresentable {
    let email: String?
    @Environment(\.dismiss) private var dismiss

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([Support.address])
        let version = Support.appVersion
        controller.setSubject(Support.subject(version: version))
        controller.setMessageBody(
            Support.body(email: email, version: version, device: Support.deviceIdentifier, system: UIDevice.current.systemVersion),
            isHTML: false
        )
        if let log = RecordingLog.shared.exportFile(), let data = try? Data(contentsOf: log) {
            controller.addAttachmentData(data, mimeType: "text/plain", fileName: "salvio-log.txt")
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            appLog("support", "письмо в поддержку: \(result.rawValue)")
            dismiss()
        }
    }
}
