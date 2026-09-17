import AVFoundation
import XCTest
@testable import Salvio

final class ChunkLogicTests: XCTestCase {
    private var root: URL!
    private var store: RecordingStore!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RecordingStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func rec(server: String? = "srv", chunks: Int, open: Int? = nil, finished: Bool = false, uploaded: Set<Int> = []) -> Recording {
        var r = Recording.new()
        r.serverId = server
        r.chunkCount = chunks
        r.openChunk = open
        r.isFinished = finished
        r.uploaded = uploaded
        return r
    }

    // MARK: - План загрузки

    func testOpenChunkIsNeverUploadedAndCallNotStartedYet() {
        XCTAssertEqual(rec(server: nil, chunks: 1, open: 0).nextSteps(inFlight: []), [])
    }

    func testCallStartsOnceFirstChunkClosed() {
        XCTAssertEqual(rec(server: nil, chunks: 2, open: 1).nextSteps(inFlight: []), [.startCall])
    }

    func testUploadsClosedChunksSkippingDoneAndInFlight() {
        let r = rec(chunks: 5, open: 4, uploaded: [0])
        XCTAssertEqual(r.nextSteps(inFlight: [2]), [.upload(1), .upload(3)])
    }

    func testFinishOnlyAfterStopAndAllChunksUploaded() {
        XCTAssertEqual(rec(chunks: 2, finished: false, uploaded: [0, 1]).nextSteps(inFlight: []), [], "пауза из-за звонка: finish рано")
        XCTAssertEqual(rec(chunks: 2, finished: true, uploaded: [0]).nextSteps(inFlight: [1]), [])
        XCTAssertEqual(rec(chunks: 2, finished: true, uploaded: [0, 1]).nextSteps(inFlight: []), [.finish])
    }

    func testEmptyFinishedRecordingIsDiscarded() {
        XCTAssertEqual(rec(server: nil, chunks: 0, finished: true).nextSteps(inFlight: []), [.discard])
        XCTAssertEqual(rec(server: nil, chunks: 0, finished: false).nextSteps(inFlight: []), [])
    }

    func testResetServerCallReuploadsEverything() {
        var r = rec(chunks: 3, finished: true, uploaded: [0, 1, 2])
        r.resetServerCall()
        XCTAssertEqual(r.nextSteps(inFlight: []), [.startCall])
        r.serverId = "new"
        XCTAssertEqual(r.nextSteps(inFlight: []), [.upload(0), .upload(1), .upload(2)])
    }

    // MARK: - Ошибки сервера

    private func failure(_ status: Int, _ body: String) -> UploadFailure {
        UploadFailure(APIError.parse(status: status, data: Data(body.utf8)))
    }

    func testFailureClassification() {
        XCTAssertEqual(failure(401, #"{"detail":{"error":"invalid_token","message":"x"}}"#), .unauthorized)
        XCTAssertEqual(failure(404, #"{"detail":{"error":"not_found","message":"Встреча не найдена"}}"#), .callLost)
        XCTAssertEqual(failure(403, #"{"detail":{"error":"forbidden","message":"x"}}"#), .callLost)
        XCTAssertEqual(failure(400, #"{"detail":{"error":"invalid_status","message":"x"}}"#), .wrongStatus)
        XCTAssertEqual(failure(400, #"{"detail":{"error":"invalid_chunks","message":"x","details":{"expected":[0,1,2],"got":[0,2]}}}"#), .chunksMismatch(got: [0, 2]))
        XCTAssertEqual(failure(500, "Internal Server Error"), .retry)
        XCTAssertEqual(failure(0, ""), .retry, "нет сети")
        XCTAssertEqual(failure(429, #"{"detail":"Too Many Requests"}"#), .retry)
    }

    func testTaskDescriptionRoundTrip() {
        let key = Uploader.parseDescription("local-1|abc123|7")
        XCTAssertEqual(key?.id, "local-1")
        XCTAssertEqual(key?.serverId, "abc123")
        XCTAssertEqual(key?.index, 7)
        XCTAssertNil(Uploader.parseDescription("garbage"))
    }

    // MARK: - Хранилище

    func testUpdateReadsFreshManifest() {
        let r = rec(server: nil, chunks: 1, open: 0)
        store.save(r)
        store.update(r.id) { $0.serverId = "s1" }
        store.update(r.id) { $0.uploaded.insert(0) }
        XCTAssertEqual(store.load(r.id)?.serverId, "s1")
        XCTAssertEqual(store.load(r.id)?.uploaded, [0])
        XCTAssertEqual(store.all().map(\.id), [r.id])
    }

    func testRecoveryAfterKillDropsEmptyLastChunkAndFinishes() throws {
        let r = rec(server: nil, chunks: 3, open: 2)
        store.save(r)
        try Data(repeating: 1, count: 4096).write(to: store.chunkURL(r.id, 0))
        try Data(repeating: 1, count: 4096).write(to: store.chunkURL(r.id, 1))
        try Data().write(to: store.chunkURL(r.id, 2))

        store.recoverInterrupted(activeId: nil)

        let recovered = try XCTUnwrap(store.load(r.id))
        XCTAssertTrue(recovered.isFinished)
        XCTAssertNil(recovered.openChunk)
        XCTAssertEqual(recovered.chunkCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.chunkURL(r.id, 2).path))
    }

    func testRecoveryKeepsActiveRecordingUntouched() {
        let r = rec(server: nil, chunks: 1, open: 0)
        store.save(r)
        store.recoverInterrupted(activeId: r.id)
        XCTAssertEqual(store.load(r.id), r)
    }

    func testMultipartBody() throws {
        let chunk = root.appendingPathComponent("c.aac")
        try Data([0xFF, 0xF1, 0x50]).write(to: chunk)
        let dest = root.appendingPathComponent("body")
        try RecordingStore.writeMultipart(chunk: chunk, index: 3, boundary: "B", to: dest)
        var expected = Data("--B\r\nContent-Disposition: form-data; name=\"chunk_index\"\r\n\r\n3\r\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk_3.aac\"\r\nContent-Type: audio/aac\r\n\r\n".utf8)
        expected.append(Data([0xFF, 0xF1, 0x50]))
        expected.append(Data("\r\n--B--\r\n".utf8))
        XCTAssertEqual(try Data(contentsOf: dest), expected)
    }

    // MARK: - Формат аудио

    /// Те же настройки, что у диктофона: AAC 16 кГц моно пишется в ADTS, а обрезанный файл
    /// (приложение убили посреди чанка) всё ещё читается.
    func testAdtsChunkSurvivesTruncation() throws {
        let url = root.appendingPathComponent("chunk_0.aac")
        do {
            let file = try AVAudioFile(forWriting: url, settings: Recorder.settings)
            let format = file.processingFormat
            let frames = AVAudioFrameCount(format.sampleRate * 3)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for i in 0..<Int(frames) { samples[i] = Float(sin(Double(i) * 2 * .pi * 440 / format.sampleRate)) * 0.5 }
            try file.write(from: buffer)
        }
        let full = try Data(contentsOf: url)
        XCTAssertGreaterThan(full.count, RecordingStore.minChunkBytes)
        XCTAssertTrue(full[0] == 0xFF && full[1] & 0xF0 == 0xF0, "ожидали ADTS-синхрослово, а не контейнер m4a")

        let truncated = root.appendingPathComponent("truncated.aac")
        try full.prefix(full.count * 6 / 10).write(to: truncated)
        let reread = try AVAudioFile(forReading: truncated)
        XCTAssertGreaterThan(reread.length, 16_000, "больше секунды аудио должно читаться из обрезанного чанка")
    }
}
