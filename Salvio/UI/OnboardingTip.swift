import SwiftUI

/// Подсказки при первом входе, как в Android 1.4.6: по одной за раз в порядке экрана, показанная больше не появляется.
/// Своя реализация на popover: TipKit только с iOS 17, а приложение поддерживает 16.2.
/// ponytail: флаги в UserDefaults на устройстве, после переустановки покажутся снова; на сервер, если понадобится синхронно с вебом.
enum Tip: String, CaseIterable {
    case recordStart, recordTemplate, listFolders, detailsTabs, detailsMenu

    var screen: String {
        switch self {
        case .recordStart, .recordTemplate: return "record"
        case .listFolders: return "list"
        case .detailsTabs, .detailsMenu: return "details"
        }
    }

    var title: String {
        switch self {
        case .recordStart: return "Запись встречи"
        case .recordTemplate: return "Шаблон итогов"
        case .listFolders: return "Поиск и папки"
        case .detailsTabs: return "Транскрипт и вопросы ИИ"
        case .detailsMenu: return "Ещё"
        }
    }

    var text: String {
        switch self {
        case .recordStart:
            return "Нажмите перед встречей. Экран можно выключить, запись продолжится, а после остановки итоги придут сами."
        case .recordTemplate:
            return "От шаблона зависит, что соберёт ИИ: итоги встречи, продажи, собеседования. Его можно сменить здесь или в профиле."
        case .listFolders:
            return "Потяните список вниз, чтобы искать по названию и словам из разговора. Здесь папки и корзина: удалённое хранится 30 дней."
        case .detailsTabs:
            return "В «Транскрипте» вся встреча по фразам: нажмите на фразу, чтобы прослушать с этого места. В «Спросить ИИ» задайте вопрос по встрече."
        case .detailsMenu:
            return "Здесь спикеры, скачивание файлом, итоги по другому шаблону, папки и удаление."
        }
    }

    /// Очередь этой подсказки: она ещё не показана, а все предыдущие с того же экрана уже закрыты.
    static func isTurn(_ tip: Tip, seen: Set<String>) -> Bool {
        guard !seen.contains(tip.rawValue) else { return false }
        let earlier = allCases.prefix { $0 != tip }.filter { $0.screen == tip.screen }
        return earlier.allSatisfy { seen.contains($0.rawValue) }
    }
}

@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()
    private static let key = "onboardingTipsSeen"
    @Published private(set) var seen: Set<String>

    init(defaults: UserDefaults = .standard) {
        seen = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func markSeen(_ tip: Tip) {
        guard !seen.contains(tip.rawValue) else { return }
        seen.insert(tip.rawValue)
        UserDefaults.standard.set(Array(seen), forKey: Self.key)
        Analytics.track("onboarding_tip_\(tip.rawValue)")
    }
}

struct OnboardingTip<Content: View>: View {
    let tip: Tip
    let enabled: Bool
    let content: Content
    @ObservedObject private var store = TipStore.shared
    @State private var presented = false

    init(_ tip: Tip, enabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.tip = tip
        self.enabled = enabled
        self.content = content()
    }

    private var turn: Bool { enabled && Tip.isTurn(tip, seen: store.seen) }

    var body: some View {
        content
            .popover(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tip.title).font(.headline)
                    Text(tip.text).fixedSize(horizontal: false, vertical: true)
                    Button("Понятно") { presented = false }.padding(.top, 4)
                }
                .padding()
                .frame(idealWidth: 300)
                .compactPopover()
            }
            .task(id: turn) {
                guard turn else { return }
                // Пауза, чтобы экран успел появиться и подсказка не открылась поверх перехода.
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled { presented = true }
            }
            // Закрыли «Понятно» или тапом мимо: подсказка увидена, следующая на этом экране получает очередь.
            .onChange(of: presented) { shown in if !shown { store.markSeen(tip) } }
    }
}

private extension View {
    /// На iPhone popover без этого превращается в лист на весь экран (до iOS 16.4 так и останется).
    @ViewBuilder func compactPopover() -> some View {
        if #available(iOS 16.4, *) {
            presentationCompactAdaptation(.popover)
        } else {
            self
        }
    }
}
