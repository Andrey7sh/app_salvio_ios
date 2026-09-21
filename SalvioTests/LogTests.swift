import XCTest
@testable import Salvio

final class LogTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesAndReadsBack() {
        let log = RecordingLog(directory: dir)
        log("rec", "старт записи")
        log("up", "чанк 0 отправлен")
        let lines = log.tail()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("[up] чанк 0 отправлен"), lines[0])
        XCTAssertTrue(lines[1].contains("[rec] старт записи"), lines[1])
        XCTAssertNotNil(log.exportFile())
    }

    /// Журнал длинной записи не должен расти бесконечно, но последние события переживают ротацию.
    func testRotationKeepsRecentLines() {
        let log = RecordingLog(directory: dir)
        for i in 0..<20_000 { log("up", "чанк \(i) отправлен") }
        log("rec", "стоп записи")

        let current = dir.appendingPathComponent("salvio.log")
        let size = ((try? FileManager.default.attributesOfItem(atPath: current.path))?[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, RecordingLog.maxBytes)
        XCTAssertTrue(log.tail().first?.contains("стоп записи") == true)
        XCTAssertGreaterThan(log.tail().count, 100, "история последних событий должна остаться")
    }

    func testClear() {
        let log = RecordingLog(directory: dir)
        log("rec", "старт")
        log.clear()
        XCTAssertTrue(log.tail().isEmpty)
        XCTAssertNil(log.exportFile())
    }
}
