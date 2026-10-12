import XCTest
@testable import Salvio

/// Те же кейсы, что в вебе (emailTypo.test.ts) и Android (EmailTypoTest.kt).
final class EmailTypoTests: XCTestCase {
    func testTyposGetSuggestion() {
        XCTAssertEqual(EmailTypo.suggest("ivan@gail.com"), "ivan@gmail.com")
        XCTAssertEqual(EmailTypo.suggest("ivan@gmial.com"), "ivan@gmail.com")
        XCTAssertEqual(EmailTypo.suggest("ivan@mail.ry"), "ivan@mail.ru")
        XCTAssertEqual(EmailTypo.suggest("ivan@mail.tu"), "ivan@mail.ru")
        XCTAssertEqual(EmailTypo.suggest("ivan@yandex.ry"), "ivan@yandex.ru")
        XCTAssertEqual(EmailTypo.suggest(" Ivan@GMAIL.CON "), "ivan@gmail.com")
        XCTAssertEqual(EmailTypo.suggest("ivan@gmail.cm"), "ivan@gmail.com")
        XCTAssertEqual(EmailTypo.suggest("ivan@ya.ry"), "ivan@ya.ru")
        XCTAssertEqual(EmailTypo.suggest("ivan@company.ry"), "ivan@company.ru")
    }

    func testNoFalsePositives() {
        for e in ["ivan@mail.ru", "ivan@kkb.chita.ru", "ivan@domozhirova.ru", "ivan@yandex.by", "ivan@ymail.com",
                  "ivan@rt.ru", "ivan@company.cm", "ivan@mail.com", "ivan", "@mail.ry", "ivan@"] {
            XCTAssertNil(EmailTypo.suggest(e), e)
        }
    }
}
