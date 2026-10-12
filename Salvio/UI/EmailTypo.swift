import Foundation

/// Подсказка при опечатке в домене почты: «Возможно, вы имели в виду mail.ru?».
/// Только подсказка, регистрацию не блокирует. Та же логика в вебе (web/src/utils/emailTypo.ts) и Android (EmailTypo.kt):
/// меняете список или правила здесь, меняйте и там, тесты на всех трёх платформах на одних кейсах.
enum EmailTypo {
    private static let popular = ["gmail.com", "mail.ru", "yandex.ru", "ya.ru", "bk.ru", "inbox.ru", "list.ru", "rambler.ru",
                                  "icloud.com", "outlook.com", "hotmail.com", "yahoo.com"]
    /// Настоящие домены в двух правках от списка: подсказка на них была бы ложной.
    private static let real: Set<String> = ["yandex.by", "yandex.kz", "yandex.ua", "yandex.uz", "mail.ua", "mail.kz", "mail.ee",
                                            "inbox.lv", "inbox.lt", "live.ru", "mail.com", "ymail.com", "gmx.com", "myrambler.ru", "rambler.ua"]
    /// Несуществующие зоны, которые получаются соседней клавишей. .cm настоящая (Камерун), её правим только до домена из списка.
    private static let zones = ["ry": "ru", "tu": "ru", "ri": "ru", "con": "com", "cm": "com"]
    private static let fakeZones: Set<String> = ["ry", "tu", "ri", "con"]

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    /// Исправленная почта целиком или nil, если подсказывать нечего.
    static func suggest(_ email: String) -> String? {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = value.lastIndex(of: "@"), at > value.startIndex else { return nil }
        let local = String(value[..<at])
        let domain = String(value[value.index(after: at)...])
        if domain.isEmpty || popular.contains(domain) || real.contains(domain) { return nil }

        var zone = ""
        var fixed = domain
        if let dot = domain.lastIndex(of: ".") {
            zone = String(domain[domain.index(after: dot)...])
            if let to = zones[zone] { fixed = String(domain[...dot]) + to }
        }

        // ponytail: у коротких ya.ru и bk.ru две правки цепляют любой двухбуквенный корпоративный домен (rt.ru),
        // поэтому для них только одна. Если пойдут ложные подсказки, порог стоит считать от длины домена.
        var best: String?
        var bestDist = Int.max
        for p in popular {
            let d = levenshtein(fixed, p)
            if d <= (p.count <= 5 ? 1 : 2) && d < bestDist { best = p; bestDist = d }
        }
        if let best { return "\(local)@\(best)" }
        // company.ry → company.ru: зоны .ry/.tu/.ri/.con не существуют, так что исправление верное и для корпоративной почты.
        if fakeZones.contains(zone) { return "\(local)@\(fixed)" }
        return nil
    }
}
