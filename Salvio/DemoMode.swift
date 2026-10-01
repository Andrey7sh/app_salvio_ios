#if DEBUG
import Foundation

/// Демо-режим для скриншотов App Store: приложение запускается с `-demoScreen <экран>`
/// (record, list, meeting, planning, lecture), ответы API берутся из фикстур ниже, сеть и вход не нужны.
/// Снимает воркфлоу `.github/workflows/appstore-screens.yml`. Только debug-сборка: в релиз не попадает.
enum DemoMode {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var isOn: Bool { screen != nil }

    /// Вкладка при запуске: 0 запись, 1 встречи.
    static var initialTab: Int { screen == "record" ? 0 : 1 }

    /// Какую встречу сразу открыть поверх списка.
    static var initialPath: [CallItem] {
        guard let id = ["meeting": "m1", "planning": "m2", "lecture": "m3"][screen ?? ""] else { return [] }
        return calls.filter { $0.id == id }
    }

    static func response(_ path: String) -> Data? {
        guard isOn else { return nil }
        let p = path.split(separator: "?").first.map(String.init) ?? path
        switch p {
        case "auth/me":
            return json(#"{"id":"demo","email":"demo@salvio.io","full_name":"Анна","email_verified":true,"default_scenario":{"id":"s1","key":"protocol","name":"Протокол встречи","icon":"📝"}}"#)
        case "workspaces":
            return json(#"{"current":"personal","wallet":"personal","personal":{"balance_minutes":300},"team":null}"#)
        case "calls":
            let items = calls.map { c in
                #"{"id":"\#(c.id)","title":"\#(c.title ?? "")","startedAt":"\#(c.startedAt ?? "")","durationSeconds":\#(c.durationSeconds ?? 0),"status":"done"}"#
            }
            return json(#"{"items":[\#(items.joined(separator: ","))],"page":1,"total_pages":1}"#)
        default:
            break
        }
        let parts = p.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "calls", let call = calls.first(where: { $0.id == parts[1] }) else { return nil }
        switch parts.count == 2 ? "" : parts[2] {
        case "":
            return json(#"{"id":"\#(call.id)","title":"\#(call.title ?? "")","status":"done","startedAt":"\#(call.startedAt ?? "")","durationSeconds":\#(call.durationSeconds ?? 0)}"#)
        case "result":
            let (scenario, sections) = results[call.id] ?? ("📝 Протокол встречи", [])
            let icon = scenario.split(separator: " ").first.map(String.init) ?? ""
            let name = scenario.split(separator: " ").dropFirst().joined(separator: " ")
            let body = sections.map { #"{"title":"\#($0.0)","value":"\#($0.1)"}"# }.joined(separator: ",")
            return json(#"{"scenario":{"name":"\#(name)","icon":"\#(icon)"},"sections":[\#(body)],"ready":true}"#)
        case "recommendations":
            return json(#"{"recommendations":{"tips":[{"title":"Закрепите договорённости письмом","description":"Отправьте итоги встречи в тот же день, пока детали свежие."}]}}"#)
        case "transcript":
            return json(#"{"segments":[{"speaker_label":"Анна","text":"Давайте зафиксируем, что успели обсудить."},{"speaker_label":"Мария","text":"Да, и сразу сроки по поставке."}]}"#)
        case "checklist":
            return json(#"{"checklist":null}"#)
        case "share":
            return json(#"{"share":null}"#)
        default:
            return nil
        }
    }

    static let calls: [CallItem] = [
        CallItem(id: "m1", title: "Встреча с клиентом «Стройкомплект»", startedAt: "2026-09-18T14:04:00+00:00", durationSeconds: 2820, status: "done"),
        CallItem(id: "m2", title: "Планёрка по ремонту офиса", startedAt: "2026-09-18T10:30:00+00:00", durationSeconds: 2280, status: "done"),
        CallItem(id: "m3", title: "Лекция по юнит-экономике", startedAt: "2026-09-17T15:00:00+00:00", durationSeconds: 5340, status: "done"),
        CallItem(id: "m4", title: "Собеседование: менеджер по продажам", startedAt: "2026-09-17T12:00:00+00:00", durationSeconds: 1980, status: "done"),
        CallItem(id: "m5", title: "Звонок от поставщика", startedAt: "2026-09-17T09:15:00+00:00", durationSeconds: 360, status: "done"),
        CallItem(id: "m6", title: "Голосовая заметка про сайт", startedAt: "2026-09-16T18:04:00+00:00", durationSeconds: 180, status: "done"),
        CallItem(id: "m7", title: "Созвон с подрядчиком по смете", startedAt: "2026-09-16T11:00:00+00:00", durationSeconds: 1500, status: "done"),
    ]

    private static let results: [String: (String, [(String, String)])] = [
        "m1": ("🔎 Выявление потребностей", [
            ("Клиент", "• Компания: ООО «Стройкомплект»\\n• Собеседник: Мария, закупщик"),
            ("Боли", "• Поставки срываются, склад пустой по 3 дня"),
            ("Ожидания", "• Поставка за 48 часов\\n• Отсрочка платежа 30 дней"),
            ("Договорённости", "• Пробная партия 200 мешков до 25 сентября\\n• КП с ценой за тонну до пятницы"),
            ("Следующий шаг", "• Созвон в понедельник в 11:00, решение по договору"),
        ]),
        "m2": ("📝 Протокол встречи", [
            ("Кратко", "Согласовали смету ремонта офиса и перенесли старт работ на 1 октября."),
            ("Участники", "• Иван, руководитель проекта\\n• Мария, сметчик\\n• Олег, прораб"),
            ("Темы и выводы", "• Смета: итог вырос на 8% из-за электрики, приняли\\n• Сроки: старт 1 октября вместо 25 сентября"),
            ("Решения", "• Утвердить смету 1 240 000 ₽\\n• Плитку заказывать у нового поставщика"),
            ("Задачи", "• Мария: обновить смету до 20 сентября\\n• Олег: график работ до 24 сентября"),
        ]),
        "m3": ("🎓 Конспект лекции", [
            ("Тема", "Юнит-экономика, лектор Мария"),
            ("Ключевые тезисы", "• Считать экономику нужно на одного клиента, а не на заказ\\n• Окупаемость привлечения важнее выручки"),
            ("Термины", "• LTV: доход с клиента за всё время\\n• CAC: стоимость привлечения клиента"),
            ("Примеры и кейсы", "• Кофейня: LTV 12 000 ₽ при CAC 800 ₽"),
            ("Цитаты", "• «Рост без юнит-экономики это рост убытков»"),
        ]),
    ]

    private static func json(_ s: String) -> Data { Data(s.utf8) }
}
#endif
