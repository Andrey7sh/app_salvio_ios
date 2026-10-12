import XCTest
@testable import Salvio

/// Ответы сняты с настоящего salvio-web (TestClient, ветка feat/transcript-pages), те же, что в Android MeetingContractTest.
final class MeetingTests: XCTestCase {
    private func plain<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.plain.decode(T.self, from: Data(json.utf8))
    }

    func testTranscriptPageKeepsSpeakerKeys() throws {
        let page = try plain(TranscriptPage.self, """
        {"segments":[{"start_ms":0,"end_ms":4000,"speaker":"A","speaker_label":"Иван","speaker_role":null,
          "text":"Смета по объекту на Ленина готова","tags":[]}],
         "total":2,"transcript_text":null,"speaker_mapping":{},"speaker_names":{"A":"Иван","spk_b":"Олег"},
         "speaker_roles":{},"visible_ratio":null}
        """)
        XCTAssertEqual(page.total, 2)
        XCTAssertEqual(page.segments.first?.endMs, 4000)
        XCTAssertEqual(page.segments.first?.speakerLabel, "Иван")
        // convertFromSnakeCase превратил бы spk_b в spkB, и сохранение затёрло бы имя на сервере.
        XCTAssertEqual(page.speakerNames["spk_b"], "Олег")
    }

    func testPreferencesKeepOptionKeysAndPatchIsPartial() throws {
        let prefs = try plain(Preferences.self, """
        {"ai_preferences":{"about":"","focus":[],"style":[]},"vocabulary":{"enabled":true,"industry":"real_estate","terms":[]},
         "transcription_language":"ru","speaker_roles":[{"id":"default-8d989115","title":"Менеджер","full_name":""}],
         "options":{"focus":["Цифры"],"style":["Кратко"],"languages":{"ru":"Русский","en":"Английский"},
                    "industries":{"real_estate":"Недвижимость"}},"notifications":{"summary_ready":true}}
        """)
        XCTAssertEqual(prefs.vocabulary?.industry, "real_estate")
        XCTAssertEqual(prefs.options?.industries["real_estate"], "Недвижимость")
        XCTAssertEqual(prefs.speakerRoles?.first?.id, "default-8d989115")

        let body = String(data: try JSONEncoder().encode(Preferences(transcriptionLanguage: "en")), encoding: .utf8)
        XCTAssertEqual(body, #"{"transcription_language":"en"}"#)
    }

    func testFoldersSummariesChatScenarios() throws {
        let folders = try JSONDecoder.api.decode(FoldersResponse.self, from: Data(#"{"all":3,"unfiled":2,"trash":1,"folders":[{"id":"f1","name":"Объекты","count":1}]}"#.utf8))
        XCTAssertEqual(folders.folders.first?.name, "Объекты")

        let tabs = try JSONDecoder.api.decode(SummariesResponse.self, from: Data("""
        {"summaries":[{"id":"s1","kind":"pipeline","title":"Основное","status":"done","is_primary":true,"auto_selected":false,
          "scenario":null,"sections":[{"key":"result","title":"Результат","emoji":null,"format":"text","columns":null,
          "data":"Обсудили ремонт кровли","value":"Обсудили ремонт кровли"}],"error":null},
          {"id":"s2","kind":"scenario","title":"Продажа","status":"queued","is_primary":false,"sections":[]}]}
        """.utf8)).summaries
        XCTAssertEqual(tabs.first?.isPrimary, true)
        XCTAssertEqual(tabs.first?.sections?.first?.text, "Обсудили ремонт кровли")
        XCTAssertTrue(tabs[1].pending)

        let chat = try JSONDecoder.api.decode(ChatResponse.self, from: Data(#"{"messages":[{"id":"m1","role":"assistant","content":"**Да**","created_at":"2026-10-12T15:00:00"}]}"#.utf8))
        XCTAssertEqual(chat.messages.first?.role, "assistant")

        let card = try JSONDecoder.api.decode(ScenariosResponse.self, from: Data(#"{"scenarios":[{"id":"s1","key":"meeting","name":"Встреча","icon":"📝","description":"Кратко","owner_type":"global"}]}"#.utf8)).scenarios[0]
        XCTAssertEqual(card.label, "📝 Встреча")
    }

    func testNoSpeechStatus() throws {
        let item = try JSONDecoder.api.decode(CallItem.self, from: Data(#"{"id":"1","status":"error","error_code":"no_speech"}"#.utf8))
        XCTAssertEqual(Format.status(item.status, errorCode: item.errorCode), "Нет речи")
        XCTAssertEqual(Format.status("error"), "Ошибка")
    }

    func testExportFileName() {
        XCTAssertEqual(Format.fileName(#"Встреча: план/факт "Q3""#), #"Встреча  план факт  Q3"#)
        XCTAssertEqual(Format.fileName("  "), "Запись")
    }

    func testTipsComeOneAtATimePerScreen() {
        func shown(_ seen: Set<String>) -> [Tip] { Tip.allCases.filter { Tip.isTurn($0, seen: seen) } }
        XCTAssertEqual(shown([]), [.recordStart, .listFolders, .detailsTabs])
        XCTAssertEqual(shown([Tip.recordStart.rawValue]), [.recordTemplate, .listFolders, .detailsTabs])
        XCTAssertEqual(shown(Set(Tip.allCases.map(\.rawValue))), [])
    }
}
