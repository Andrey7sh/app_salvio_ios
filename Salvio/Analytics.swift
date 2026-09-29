import AppMetricaCore
import AppMetricaCrashes
import Foundation

/// AppMetrica: события и краши. Ключ не секрет, он всё равно лежит в сборке. Один ключ на Android и iOS.
/// Тексты встреч, e-mail и токены сюда не отправляем, только имена событий.
enum Analytics {
    static func activate() {
        // Под XCTest не шлём: иначе прогоны CI попадут в статистику.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let config = AppMetricaConfiguration(apiKey: "6bd2e83a-0b97-4077-8fad-84faead524b9") else { return }
        config.locationTracking = false
        AppMetrica.activate(with: config)
    }

    static func track(_ name: String) {
        AppMetrica.reportEvent(name: name, onFailure: nil)
    }
}
