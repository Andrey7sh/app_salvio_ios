import XCTest
@testable import Salvio

final class APIParsingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    func testLoginWithScenarioProfile() throws {
        let pair = try decode(TokenPair.self, """
        {"access_token":"a","refresh_token":"r","token_type":"bearer",
         "user":{"id":"5b1c","email":"a@b.ru","full_name":"Андрей","role":"manager","status":"active",
                 "company_id":null,"default_scenario_id":"s1","email_verified":false,
                 "default_scenario":{"id":"s1","key":"interview","name":"Собеседование","icon":"🧑‍💼",
                   "output_schema":[{"key":"experience","title":"Опыт"}],"has_checklist":false}}}
        """)
        XCTAssertEqual(pair.accessToken, "a")
        XCTAssertEqual(pair.user?.emailVerified, false)
        XCTAssertEqual(pair.user?.defaultScenario?.label, "🧑‍💼 Собеседование")
        XCTAssertEqual(pair.user?.defaultScenario?.outputSchema?.first?.title, "Опыт")
    }

    func testUserWithoutScenario() throws {
        let user = try decode(User.self, #"{"id":"1","email":"a@b.ru","full_name":"A","default_scenario":null}"#)
        XCTAssertNil(user.defaultScenario?.label)
    }

    func testBalance() throws {
        let b = try decode(Balance.self, #"{"account_id":"x","owner_type":"user","balance_seconds":1799,"balance_minutes":29,"low_balance":false}"#)
        XCTAssertEqual(b, Balance(balanceMinutes: 29, lowBalance: false))
    }

    func testCallsListCamelCaseKeys() throws {
        let page = try decode(CallsPage.self, """
        {"items":[{"id":"c1","title":"Встреча","managerId":"u","startedAt":"2026-09-17T10:00:00.123456+00:00",
                   "durationSeconds":null,"status":"awaiting_payment","scoreAverage":null,"leadScore":null}],
         "page":1,"limit":20,"total":1,"total_pages":1}
        """)
        XCTAssertEqual(page.totalPages, 1)
        XCTAssertEqual(page.items.first?.status, "awaiting_payment")
        XCTAssertNil(page.items.first?.durationSeconds)
        XCTAssertNotNil(ISO8601DateFormatter.parseFlexible(page.items.first?.startedAt))
    }

    func testResultSectionsOfAnyShape() throws {
        let r = try decode(CallResult.self, """
        {"scenario":{"id":"s","name":"Планёрка","icon":null,"output_schema":[]},
         "sections":[
           {"key":"summary","title":"Итоги","value":"  Договорились  "},
           {"key":"tasks","title":"Задачи","value":["Отчёт","Звонок"]},
           {"key":"owner","title":"Ответственные","value":{"Иван":"отчёт","Анна":2}}
         ],"status":"done","ready":true}
        """)
        XCTAssertTrue(r.ready)
        XCTAssertEqual(r.scenario?.label, "Планёрка")
        XCTAssertEqual(r.sections.map(\.text), ["Договорились", "• Отчёт\n• Звонок", "Анна: 2\nИван: отчёт"])
    }

    /// Упавшая генерация: без текста сбоя экран показывал бы «ещё не сформированы» вечно.
    func testResultCarriesSummaryError() throws {
        let r = try decode(CallResult.self, """
        {"scenario":null,"sections":[],"status":"done","ready":false,"error":"Саммари не получено"}
        """)
        XCTAssertFalse(r.ready)
        XCTAssertEqual(r.error, "Саммари не получено")
    }

    func testChecklistVerdicts() throws {
        let c = try decode(ChecklistResponse.self, """
        {"checklist":{"checklist_name":"Продажи","score_average":7.5,"categories":[
          {"name":"Выявление","weight":1.0,"items":[
            {"criterion":"Задал вопросы","value":"yes","score":1},
            {"criterion":"Резюмировал","value":"partial"},
            {"criterion":"Назначил шаг","value":"no","comment":null}]}]},"score_average":7.5}
        """)
        XCTAssertEqual(c.checklist?.categories.first?.items.map(\.verdict), ["Да", "Частично", "Нет"])
    }

    func testTranscriptPlaceholder202() throws {
        let t = try decode(Transcript.self, #"{"segments":[],"transcript_text":"","status":"transcribing"}"#)
        XCTAssertTrue(t.segments.isEmpty)
    }

    func testTranscriptSegments() throws {
        let t = try decode(Transcript.self, """
        {"segments":[{"start_ms":0,"end_ms":900,"speaker":"A","speaker_label":"Менеджер","speaker_role":"Менеджер","text":"Привет","tags":[]}],
         "transcript_text":"Привет","speaker_mapping":{}}
        """)
        XCTAssertEqual(t.segments.first?.speakerLabel, "Менеджер")
        XCTAssertEqual(t.segments.first?.startMs, 0)
    }

    func testShare() throws {
        let s = try decode(ShareLinkInfo.self, #"{"id":"1","token":"ab","url":"https://app.salvio.io/s/ab","sections":["summary"],"view_count":0,"revoked":false}"#)
        XCTAssertEqual(s.url, "https://app.salvio.io/s/ab")
        XCTAssertNil(try decode(ShareLookup.self, #"{"share":null}"#).share)
    }

    func testApiErrorFormats() {
        let e1 = APIError.parse(status: 400, data: Data(#"{"detail":{"error":"invalid_chunks","message":"Не хватает чанков","details":{"expected":[0,1,2],"got":[0,2]}}}"#.utf8))
        XCTAssertEqual(e1.code, "invalid_chunks")
        XCTAssertEqual(e1.details?["got"], JSONValue.array([.number(0), .number(2)]))

        let e2 = APIError.parse(status: 400, data: Data(#"{"detail":"Email уже зарегистрирован"}"#.utf8))
        XCTAssertEqual(e2.message, "Email уже зарегистрирован")

        let e3 = APIError.parse(status: 422, data: Data(#"{"detail":[{"loc":["body","email"],"msg":"value is not a valid email address","type":"value_error"}]}"#.utf8))
        XCTAssertEqual(e3.message, "value is not a valid email address")

        XCTAssertEqual(APIError.parse(status: 502, data: Data("<html>".utf8)).message, "Сервер временно недоступен")
    }

    func testFormEncoding() {
        XCTAssertEqual(APIClient.formEncode([("title", "Встреча 17.09 10:00"), ("duration_seconds", "0"), ("started_at", "2026-09-17T10:00:00+03:00")]),
                       "title=%D0%92%D1%81%D1%82%D1%80%D0%B5%D1%87%D0%B0%2017.09%2010%3A00&duration_seconds=0&started_at=2026-09-17T10%3A00%3A00%2B03%3A00")
    }

    func testRequestUrlKeepsQuery() {
        let r = APIClient.makeRequest("GET", "calls?page=2&limit=20", body: nil, token: "t")
        XCTAssertEqual(r.url?.absoluteString, "https://app.salvio.io/api/calls?page=2&limit=20")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }
}
