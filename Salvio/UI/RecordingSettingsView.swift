import SwiftUI

/// Настройки записи как на странице профиля веб-кабинета (PreferencesForm.tsx). Хранятся на сервере,
/// поэтому правка здесь сразу видна в вебе, и наоборот.
@MainActor
final class PreferencesModel: ObservableObject {
    @Published private(set) var prefs: Preferences?
    @Published var error: String?

    func load() async {
        do { prefs = try await MeetingAPI.preferences(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    /// PUT частичный: передаём только изменённое поле, сервер возвращает настройки целиком.
    func save(_ patch: Preferences) async {
        do { prefs = try await MeetingAPI.savePreferences(patch); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct RecordingSettingsSection: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = PreferencesModel()
    @State private var pickingScenario = false

    var body: some View {
        Section {
            Button {
                pickingScenario = true
            } label: {
                LabeledContent("Шаблон по умолчанию", value: session.user?.defaultScenario?.label ?? "не выбран")
            }
            .foregroundColor(.primary)
            if let prefs = model.prefs {
                let languages = prefs.options?.languages ?? [:]
                Picker("Язык распознавания", selection: Binding(
                    get: { prefs.transcriptionLanguage ?? "ru" },
                    set: { code in Task { await model.save(Preferences(transcriptionLanguage: code)) } })) {
                    ForEach(languages.keys.sorted { languageOrder($0, $1, languages) }, id: \.self) { code in
                        Text(languages[code] ?? code).tag(code)
                    }
                }
                NavigationLink {
                    VocabularyForm(prefs: prefs) { await model.save(Preferences(vocabulary: $0)) }
                } label: {
                    LabeledContent("Словарь терминов", value: vocabularySummary(prefs))
                }
                NavigationLink {
                    RolesForm(roles: prefs.speakerRoles ?? []) { await model.save(Preferences(speakerRoles: $0)) }
                } label: {
                    LabeledContent("Роли спикеров", value: (prefs.speakerRoles ?? []).map(\.title).joined(separator: ", ").ifEmpty("не заданы"))
                }
                NavigationLink {
                    AIForm(prefs: prefs) { await model.save(Preferences(aiPreferences: $0)) }
                } label: {
                    let ai = prefs.aiPreferences ?? .init()
                    LabeledContent("Персонализация итогов", value: (ai.focus + ai.style).joined(separator: ", ").ifEmpty("по умолчанию"))
                }
            }
            if let error = model.error {
                Text(error).foregroundColor(.red)
            }
        } header: {
            Text("Настройки записи")
        } footer: {
            Text("Общие с веб-кабинетом. Язык и словарь действуют на новые записи.")
        }
        .task { await model.load() }
        .sheet(isPresented: $pickingScenario) {
            ScenarioPickerView(title: "Шаблон по умолчанию") { scenario in
                Task {
                    do { try await session.setDefaultScenario(scenario.id) }
                    catch { model.error = error.localizedDescription }
                }
            }
        }
    }

    /// Русский первым, дальше по названию: порядок словаря на сервере не гарантирован.
    private func languageOrder(_ a: String, _ b: String, _ names: [String: String]) -> Bool {
        if a == "ru" { return b != "ru" }
        if b == "ru" { return false }
        return (names[a] ?? a) < (names[b] ?? b)
    }

    private func vocabularySummary(_ prefs: Preferences) -> String {
        let v = prefs.vocabulary ?? .init()
        if !v.enabled { return "выключен" }
        let parts = [v.industry.flatMap { prefs.options?.industries[$0] }, v.terms.isEmpty ? nil : "\(v.terms.count) слов"].compactMap { $0 }
        return parts.isEmpty ? "пусто" : parts.joined(separator: ", ")
    }
}

private struct VocabularyForm: View {
    let prefs: Preferences
    let onSave: (Preferences.Vocabulary) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var industry = ""
    @State private var terms = ""

    var body: some View {
        Form {
            Section {
                Toggle("Использовать словарь", isOn: $enabled)
                Picker("Отрасль", selection: $industry) {
                    Text("Не выбрана").tag("")
                    ForEach((prefs.options?.industries ?? [:]).sorted { $0.value < $1.value }, id: \.key) { Text($0.value).tag($0.key) }
                }
            }
            Section {
                TextEditor(text: $terms).frame(minHeight: 160)
            } header: {
                Text("Слова, по одному в строке")
            } footer: {
                Text("Имена, названия компаний и термины, которые распознавание пишет с ошибками.")
            }
        }
        .navigationTitle("Словарь терминов")
        .toolbar {
            Button("Сохранить") {
                var seen = Set<String>()
                let list = terms.split(whereSeparator: { $0 == "\n" || $0 == "," })
                    .map { String($0.trimmingCharacters(in: .whitespaces).prefix(60)) }
                    .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
                let vocab = Preferences.Vocabulary(enabled: enabled, industry: industry.isEmpty ? nil : industry,
                                                   terms: Array(list.prefix(Preferences.maxTerms)))
                Task { await onSave(vocab); dismiss() }
            }
        }
        .onAppear {
            let v = prefs.vocabulary ?? .init()
            enabled = v.enabled
            industry = v.industry ?? ""
            terms = v.terms.joined(separator: "\n")
        }
    }
}

/// Справочник ролей: id сохраняем, иначе роли, уже назначенные спикерам в записях, потеряются.
private struct RolesForm: View {
    @State var roles: [Preferences.SpeakerRole]
    let onSave: ([Preferences.SpeakerRole]) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach($roles) { $role in
                    VStack(alignment: .leading) {
                        TextField("Роль", text: $role.title)
                        TextField("ФИО, если всегда один человек", text: $role.fullName).font(.footnote)
                    }
                }
                .onDelete { roles.remove(atOffsets: $0) }
                if roles.count < Preferences.maxRoles {
                    Button("+ Добавить роль") { roles.append(Preferences.SpeakerRole(id: UUID().uuidString, title: "")) }
                }
            } footer: {
                Text("Роли выбираются у спикеров в транскрипте. Если указать ФИО, оно подставится вместо названия роли.")
            }
        }
        .navigationTitle("Роли спикеров")
        .toolbar {
            Button("Сохранить") {
                // id новой роли: UUID из 36 символов, сервер принимает такой как есть (clean_speaker_roles).
                let clean = roles.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { Preferences.SpeakerRole(id: $0.id, title: String($0.title.prefix(60)), fullName: String($0.fullName.prefix(120))) }
                Task { await onSave(clean); dismiss() }
            }
        }
    }
}

private struct AIForm: View {
    let prefs: Preferences
    let onSave: (Preferences.AIPreferences) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ai = Preferences.AIPreferences()

    var body: some View {
        Form {
            Section("О вас и вашей работе") {
                TextEditor(text: $ai.about).frame(minHeight: 100)
            }
            Section("На чём делать акцент") {
                ForEach(prefs.options?.focus ?? [], id: \.self) { toggle($0, in: \.focus) }
            }
            Section("Стиль") {
                ForEach(prefs.options?.style ?? [], id: \.self) { toggle($0, in: \.style) }
            }
        }
        .navigationTitle("Персонализация итогов")
        .toolbar {
            Button("Сохранить") {
                var value = ai
                value.about = String(value.about.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                Task { await onSave(value); dismiss() }
            }
        }
        .onAppear { ai = prefs.aiPreferences ?? .init() }
    }

    private func toggle(_ option: String, in path: WritableKeyPath<Preferences.AIPreferences, [String]>) -> some View {
        Toggle(option, isOn: Binding(
            get: { ai[keyPath: path].contains(option) },
            set: { on in
                if on { ai[keyPath: path].append(option) } else { ai[keyPath: path].removeAll { $0 == option } }
            }))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
