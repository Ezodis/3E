import XCTest
@testable import PC205Core

final class PC205CoreTests: XCTestCase {
    /// Vendor Cfg.ini defaults with KeyCodeHasIndex=1 (see PROTOCOL.md §5).
    func testVendorDefaultEntries() {
        let row = Profile.vendorDefault.buttons[0]
        let entries = row.enumerated().map { $0.element.entry(slot: $0.offset + 1) }
        XCTAssertEqual(entries, [0xF011, 0xF112, 0xF213, 0xF314, 0xF415, 0x2046, 0x4047, 0x0138, 0x0759, 0x075A])
    }

    func testSideButtonKeys() {
        XCTAssertEqual(ButtonAction.keyPress(HIDKey.f13).entry(slot: 8), 0x0068_0068)
        XCTAssertEqual(ButtonAction.keyPress(HIDKey.pause).entry(slot: 8), 0x0048_0068)
        XCTAssertEqual(ButtonAction.key(modifiers: [.leftControl, .leftShift], key: 0x04, key2: 0).encode(), 0x0004_0360)
    }

    func testRoundTrip() {
        let actions: [ButtonAction] = [
            .mouse(.left), .mouse(.forward), .doubleClick, .tripleClick, .keyPress(0x68),
            .fire(key: 0xF0, intervalMs: 40, count: 3), .media(.volumeUp), .media(.wwwSearch),
            .dpiUp, .dpiDown, .dpiLoop, .dpiLock(dpi: 800), .disabled, .switchPollingRate,
            .switchLighting, .macro(index: 3, mode: .whileHeld),
        ]
        for a in actions {
            XCTAssertEqual(ButtonAction.decode(a.entry(slot: 5)), a, a.label)
        }
    }

    func testMediaEncoding() {
        XCTAssertEqual(ButtonAction.media(.playPause).encode(), 0x0870)
        XCTAssertEqual(ButtonAction.media(.calculator).encode(), 0x20_0070)
        XCTAssertEqual(ButtonAction.media(.wwwRefresh).encode(), 0x2000_0070)
    }

    func testMacroEncoding() {
        let m = Macro(name: "t", events: [
            MacroEvent(key: 0x04, press: true, delayMs: 0),
            MacroEvent(key: 0x04, press: false, delayMs: 50),
            MacroEvent(key: 0x05, press: true, delayMs: 350),
        ], repeatCount: 0x0102)
        let b = m.encode()
        XCTAssertEqual(b.count, 128)
        XCTAssertEqual(Array(b[0..<12]), [0x01, 0x02, 0x81, 0x04, 0x32, 0x04, 0x80 | 50, 0x05, 3, 0x03, 0, 0])
        let d = Macro.decode(b, name: "t")
        XCTAssertEqual(d.events.map(\.key), [0x04, 0x04, 0x05])
        XCTAssertEqual(d.events.map(\.delayMs), [1, 50, 350])
        XCTAssertEqual(d.events.map(\.press), [true, false, true])
    }

    func testMatrixLayout() {
        var p = Profile.lolDefault
        p.macros[0] = Macro(name: "m", events: Macro.tap(0x04))
        p.buttons[1][9] = .macro(index: 1, mode: .count)
        let x = p.matrixPayload()
        XCTAssertEqual(x.count, 0x478)
        XCTAssertEqual(Array(x[0..<4]), [0x00, 0x01, 0x80 | 20, 0x04])
        // mode 0, slot 8 → F13
        let o = 0x400 + 7 * 4
        XCTAssertEqual(Array(x[o..<o + 4]), [0x68, 0x00, 0x68, 0x00])
        // mode 1, slot 10 → macro 1, count mode
        let o2 = 0x400 + (10 + 9) * 4
        XCTAssertEqual(Array(x[o2..<o2 + 4]), [0x9A, 0x11, 0x00, 0x00])
        XCTAssertEqual(PC205.matrixPayload + 1, 1145)
    }

    func testGeneralReport() {
        var payload = [UInt8](repeating: 0, count: 58)
        payload[0] = 8
        payload.replaceSubrange(52..<58, with: PC205.signature)
        var g = GeneralReport(payload: payload)
        XCTAssertTrue(g.signatureOK)
        Profile.vendorDefault.apply(to: &g)
        XCTAssertEqual(g.bytes[1] & 0x0F, 5)          // 5 enabled stages
        XCTAssertEqual(g.bytes[1] >> 4, 1)            // current stage 1
        XCTAssertEqual(Array(g.bytes[4..<12]), [4, 7, 10, 14, 16, 0x90, 0x90, 0x90])
        XCTAssertEqual(Array(g.bytes[43..<48]), [1, 3, 2, 6, 5])
        XCTAssertEqual(g.bytes[20] >> 4, 3)           // breathing = index 2 → 3
        XCTAssertTrue(g.signatureOK)                  // untouched
        XCTAssertEqual(g.stages[0].x, 1200)
        XCTAssertEqual(g.featureBytes.count, 59)
    }

    func testModeReport() {
        var m = ModeReport(payload: [1, 3, 3, 3, 2, 3, 1, 0])
        Profile.vendorDefault.apply(to: &m)
        m.setRate(.hz1000, mode: 2)
        XCTAssertEqual(m.featureBytes, [8, 1, 3, 3, 4, 2, 3, 1, 0])
    }
}
