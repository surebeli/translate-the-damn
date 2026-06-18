import XCTest
@testable import TranslateTheDamnCore

final class CarbonKeyMapTests: XCTestCase {

    func testCarbonKeyCodeLetterA() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 65), 0x00)
    }

    func testCarbonKeyCodeLetterT() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 84), 0x11)
    }

    func testCarbonKeyCodeLetterZ() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 90), 0x06)
    }

    func testCarbonKeyCodeAllLettersAreNonNil() throws {
        for vk in 65...90 {
            XCTAssertNotNil(CarbonKeyMap.carbonKeyCode(fromVK: vk), "VK \(vk) should map to a Carbon keycode")
        }
    }

    func testCarbonKeyCodeDigit0() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 48), 0x1D)
    }

    func testCarbonKeyCodeDigit9() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 57), 0x1A)
    }

    func testCarbonKeyCodeAllDigitsAreNonNil() throws {
        for vk in 48...57 {
            XCTAssertNotNil(CarbonKeyMap.carbonKeyCode(fromVK: vk), "VK \(vk) should map to a Carbon keycode")
        }
    }

    func testCarbonKeyCodeF1() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 112), 0x7A)
    }

    func testCarbonKeyCodeF2() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 113), 0x78)
    }

    func testCarbonKeyCodeF12() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 123), 0x6F)
    }

    func testCarbonKeyCodeF1ThroughF20AreNonNil() throws {
        for vk in 112...131 {
            XCTAssertNotNil(CarbonKeyMap.carbonKeyCode(fromVK: vk), "VK \(vk) (F\(vk - 111)) should map to a Carbon keycode")
        }
    }

    func testCarbonKeyCodeSpace() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 32), 0x31)
    }

    func testCarbonKeyCodeEscape() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 27), 0x35)
    }

    func testCarbonKeyCodeTab() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 9), 0x30)
    }

    func testCarbonKeyCodeReturn() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 13), 0x24)
    }

    func testCarbonKeyCodeBackspace() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 8), 0x33)
    }

    func testCarbonKeyCodeForwardDelete() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 46), 0x75)
    }

    func testCarbonKeyCodeLeftArrow() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 37), 0x7B)
    }

    func testCarbonKeyCodeUpArrow() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 38), 0x7E)
    }

    func testCarbonKeyCodeRightArrow() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 39), 0x7C)
    }

    func testCarbonKeyCodeDownArrow() throws {
        XCTAssertEqual(CarbonKeyMap.carbonKeyCode(fromVK: 40), 0x7D)
    }

    func testCarbonKeyCodeInvalidVKReturnsNil() throws {
        XCTAssertNil(CarbonKeyMap.carbonKeyCode(fromVK: -1))
        XCTAssertNil(CarbonKeyMap.carbonKeyCode(fromVK: 999))
        XCTAssertNil(CarbonKeyMap.carbonKeyCode(fromVK: 0))
    }

    func testCarbonModifiersAllOff() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: false, hasAlt: false, hasShift: false, hasWin: false)
        XCTAssertEqual(m, 0)
    }

    func testCarbonModifiersAllOn() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: true, hasAlt: true, hasShift: true, hasWin: true)
        XCTAssertEqual(m, 0x0100 | 0x0800 | 0x0200)
    }

    func testCarbonModifiersControlOnly() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: true, hasAlt: false, hasShift: false, hasWin: false)
        XCTAssertEqual(m, 0x0100)
    }

    func testCarbonModifiersAltOnly() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: false, hasAlt: true, hasShift: false, hasWin: false)
        XCTAssertEqual(m, 0x0800)
    }

    func testCarbonModifiersShiftOnly() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: false, hasAlt: false, hasShift: true, hasWin: false)
        XCTAssertEqual(m, 0x0200)
    }

    func testCarbonModifiersWinOnly() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: false, hasAlt: false, hasShift: false, hasWin: true)
        XCTAssertEqual(m, 0x0100)
    }

    func testCarbonModifiersCtrlAlt() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: true, hasAlt: true, hasShift: false, hasWin: false)
        XCTAssertEqual(m, 0x0900)
    }

    func testCarbonModifiersWinShift() throws {
        let m = CarbonKeyMap.carbonModifiers(hasControl: false, hasAlt: false, hasShift: true, hasWin: true)
        XCTAssertEqual(m, 0x0300)
    }
}
