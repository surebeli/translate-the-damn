import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class ClipboardFilterTests: XCTestCase {

    // MARK: - Static shouldProcess

    func testShouldProcessAcceptsValidText() {
        XCTAssertTrue(ClipboardFilter.shouldProcess(newText: "hello", lastProcessed: nil, maxChars: 100))
    }

    func testShouldProcessRejectsEmptyString() {
        XCTAssertFalse(ClipboardFilter.shouldProcess(newText: "", lastProcessed: nil, maxChars: 100))
    }

    func testShouldProcessRejectsWhitespaceOnly() {
        XCTAssertFalse(ClipboardFilter.shouldProcess(newText: "   \n\t  ", lastProcessed: nil, maxChars: 100))
    }

    func testShouldProcessRejectsTextOverMaxChars() {
        XCTAssertFalse(ClipboardFilter.shouldProcess(newText: String(repeating: "a", count: 11), lastProcessed: nil, maxChars: 10))
    }

    func testShouldProcessAcceptsTextAtMaxCharsBoundary() {
        XCTAssertTrue(ClipboardFilter.shouldProcess(newText: String(repeating: "a", count: 10), lastProcessed: nil, maxChars: 10))
    }

    func testShouldProcessRejectsDuplicateOfLastProcessed() {
        XCTAssertFalse(ClipboardFilter.shouldProcess(newText: "same", lastProcessed: "same", maxChars: 100))
    }

    func testShouldProcessAcceptsDifferentTextAfterLastProcessed() {
        XCTAssertTrue(ClipboardFilter.shouldProcess(newText: "new", lastProcessed: "old", maxChars: 100))
    }

    // MARK: - Hash / self-write guard

    func testHashIsStable() {
        XCTAssertEqual(ClipboardFilter.hash("hello"), ClipboardFilter.hash("hello"))
        XCTAssertNotEqual(ClipboardFilter.hash("hello"), ClipboardFilter.hash("world"))
    }

    func testMarkedSelfWriteIsRecognized() {
        let filter = ClipboardFilter(maxChars: 100)
        filter.markSelfWrite(text: "self-written")
        XCTAssertTrue(filter.isSelfWrite(text: "self-written"))
    }

    func testSelfWriteGuardIsConsumedOnce() {
        let filter = ClipboardFilter(maxChars: 100)
        filter.markSelfWrite(text: "self-written")
        XCTAssertTrue(filter.isSelfWrite(text: "self-written"))
        XCTAssertFalse(filter.isSelfWrite(text: "self-written"))
    }

    func testUnmarkedTextIsNotSelfWrite() {
        let filter = ClipboardFilter(maxChars: 100)
        XCTAssertFalse(filter.isSelfWrite(text: "random"))
    }

    // MARK: - Instance shouldProcess integrates filters

    func testInstanceRejectsEmptyText() {
        let filter = ClipboardFilter(maxChars: 100)
        XCTAssertFalse(filter.shouldProcess(newText: "   "))
    }

    func testInstanceRejectsOverlongText() {
        let filter = ClipboardFilter(maxChars: 5)
        XCTAssertFalse(filter.shouldProcess(newText: "123456"))
    }

    func testInstanceRejectsSelfWrite() {
        let filter = ClipboardFilter(maxChars: 100)
        filter.markSelfWrite(text: "loop")
        XCTAssertFalse(filter.shouldProcess(newText: "loop"))
    }

    func testInstanceAcceptsFirstValidText() {
        let filter = ClipboardFilter(maxChars: 100)
        XCTAssertTrue(filter.shouldProcess(newText: "first"))
    }

    func testInstanceDedupesConsecutiveIdenticalText() {
        let filter = ClipboardFilter(maxChars: 100)
        XCTAssertTrue(filter.shouldProcess(newText: "duplicate"))
        filter.markProcessed(text: "duplicate")
        XCTAssertFalse(filter.shouldProcess(newText: "duplicate"))
    }

    // MARK: - Debounce with injectable clock

    func testDebounceIgnoresBurstWithinInterval() {
        var now = Date(timeIntervalSince1970: 1000)
        let filter = ClipboardFilter(maxChars: 100, debounceIntervalMs: 250, clock: { now })

        XCTAssertTrue(filter.shouldProcess(newText: "a"))
        filter.markProcessed(text: "a")

        now.addTimeInterval(0.1) // 100 ms < 250 ms
        XCTAssertFalse(filter.shouldProcess(newText: "b"))
    }

    func testDebounceAcceptsAfterInterval() {
        var now = Date(timeIntervalSince1970: 1000)
        let filter = ClipboardFilter(maxChars: 100, debounceIntervalMs: 250, clock: { now })

        XCTAssertTrue(filter.shouldProcess(newText: "a"))
        filter.markProcessed(text: "a")

        now.addTimeInterval(0.3) // 300 ms > 250 ms
        XCTAssertTrue(filter.shouldProcess(newText: "b"))
    }

    func testDebounceIntervalIsInclusiveAtBoundary() {
        var now = Date(timeIntervalSince1970: 1000)
        let filter = ClipboardFilter(maxChars: 100, debounceIntervalMs: 250, clock: { now })

        XCTAssertTrue(filter.shouldProcess(newText: "a"))
        filter.markProcessed(text: "a")

        now.addTimeInterval(0.25) // exactly 250 ms
        XCTAssertTrue(filter.shouldProcess(newText: "b"))
    }
}
