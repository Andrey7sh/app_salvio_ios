import XCTest
@testable import Salvio

final class UILogicTests: XCTestCase {
    func testRegisterValidation() {
        XCTAssertEqual(AuthForm.registerError(name: " ", email: "a@b.ru", password: "123456", repeat: "123456", agreed: true), "Заполните все поля")
        XCTAssertEqual(AuthForm.registerError(name: "A", email: "ab.ru", password: "123456", repeat: "123456", agreed: true), "Проверьте e-mail")
        XCTAssertEqual(AuthForm.registerError(name: "A", email: "a@b.ru", password: "12345", repeat: "12345", agreed: true), "Пароль должен быть не короче 6 символов")
        XCTAssertEqual(AuthForm.registerError(name: "A", email: "a@b.ru", password: "123456", repeat: "123457", agreed: true), "Пароли не совпадают")
        XCTAssertEqual(AuthForm.registerError(name: "A", email: "a@b.ru", password: "123456", repeat: "123456", agreed: false), "Необходимо принять политику конфиденциальности")
        XCTAssertNil(AuthForm.registerError(name: "A", email: " A@B.ru ", password: "123456", repeat: "123456", agreed: true))
        XCTAssertEqual(AuthForm.normalize(" A@B.ru \n"), "a@b.ru")
    }

    func testLoginValidation() {
        XCTAssertEqual(AuthForm.loginError(email: "", password: "x", agreed: true), "Введите e-mail и пароль")
        XCTAssertEqual(AuthForm.loginError(email: "a@b.ru", password: "x", agreed: false), "Необходимо принять политику конфиденциальности")
        XCTAssertNil(AuthForm.loginError(email: "a@b.ru", password: "x", agreed: true))
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(0), "00:00")
        XCTAssertEqual(Format.duration(65.9), "01:05")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
    }

    func testStatuses() {
        XCTAssertEqual(Format.status("awaiting_payment"), "Ждёт оплаты")
        XCTAssertFalse(Format.isProcessing("awaiting_payment"))
        XCTAssertFalse(Format.isProcessing("done"))
        XCTAssertTrue(Format.isProcessing("transcribing"))
    }

    func testShareText() {
        let sections = [
            ResultSection(key: "a", title: "Итоги", value: .string("Договорились")),
            ResultSection(key: "b", title: "Пусто", value: .string("  ")),
            ResultSection(key: "c", title: "Задачи", value: .array([.string("Отчёт")])),
        ]
        XCTAssertEqual(Format.shareText(title: "Планёрка", sections: sections), "Планёрка\n\nИтоги:\nДоговорились\n\nЗадачи:\n• Отчёт")
    }
}
