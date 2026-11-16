import XCTest
@testable import MouseCore

/// Generic 3£ Mouse model + PC205 protocol (Shared/PC205/PROTOCOL.md). No device access.
final class MouseCoreTests: XCTestCase {
    func testVendorDefaultEntries() {
        let row = PC205.defaultProfile(lolSideKey: false).buttons[0]
        let entries = row.enumerated().map { PC205Codec.entry($0.element, slot: $0.offset + 1) }
        XCTAssertEqual(entries, [0xF011, 0xF112, 0xF213, 0xF314, 0xF415, 0x2046, 0x4047, 0x0138, 0x0759, 0x075A])
    }

    func testSideButtonKeys() {
        XCTAssertEqual(PC205Codec.entry(.keyPress(HIDKey.f13), slot: 8), 0x0068_0068)
        XCTAssertEqual(PC205Codec.entry(.keyPress(HIDKey.pause), slot: 8), 0x0048_0068)
        XCTAssertEqual(PC205Codec.encode(.key(modifiers: [.leftControl, .leftShift], key: 0x04, key2: 0)), 0x0004_0360)
        XCTAssertTrue(PC205.defaultProfile().buttons.allSatisfy { $0[PC205.extraSideSlot - 1] == .keyPress(HIDKey.f13) })
    }

    func testRoundTrip() {
        let actions: [ButtonAction] = [
            .mouse(.left), .mouse(.forward), .doubleClick, .tripleClick, .keyPress(0x68),
            .fire(key: 0xF0, intervalMs: 40, count: 3), .media(.volumeUp), .media(.wwwSearch),
            .dpiUp, .dpiDown, .dpiLoop, .dpiLock(dpi: 800), .disabled, .switchPollingRate,
            .switchLighting, .macro(index: 3, mode: .whileHeld),
        ]
        for a in actions { XCTAssertEqual(PC205Codec.decode(PC205Codec.entry(a, slot: 5)), a, a.label) }
        XCTAssertEqual(Set(actions.map(\.kind)).count, ActionKind.allCases.count - 1) // all but .raw
    }

    func testMediaEncoding() {
        XCTAssertEqual(PC205Codec.encode(.media(.playPause)), 0x0870)
        XCTAssertEqual(PC205Codec.encode(.media(.calculator)), 0x20_0070)
        XCTAssertEqual(PC205Codec.encode(.media(.wwwRefresh)), 0x2000_0070)
    }

    func testMacroEncoding() {
        let m = Macro(name: "t", events: [
            MacroEvent(key: 0x04, press: true, delayMs: 0),
            MacroEvent(key: 0x04, press: false, delayMs: 50),
            MacroEvent(key: 0x05, press: true, delayMs: 350),
        ], repeatCount: 0x0102)
        let b = PC205Codec.encode(m)
        XCTAssertEqual(b.count, 128)
        XCTAssertEqual(Array(b[0..<12]), [0x01, 0x02, 0x81, 0x04, 0x32, 0x04, 0x80 | 50, 0x05, 3, 0x03, 0, 0])
        let d = PC205Codec.decodeMacro(b, name: "t")
        XCTAssertEqual(d.events.map(\.delayMs), [1, 50, 350])
        XCTAssertEqual(d.events.map(\.press), [true, false, true])
    }

    func testMatrixLayout() {
        var p = PC205.defaultProfile()
        p.macros[0] = Macro(name: "m", events: Macro.tap(0x04))
        p.buttons[1][9] = .macro(index: 1, mode: .count)
        let x = PC205Codec.matrixPayload(p)
        XCTAssertEqual(x.count, 0x478)
        XCTAssertEqual(Array(x[0..<4]), [0x00, 0x01, 0x80 | 20, 0x04])
        let o = 0x400 + 7 * 4
        XCTAssertEqual(Array(x[o..<o + 4]), [0x68, 0x00, 0x68, 0x00])
        let o2 = 0x400 + (10 + 9) * 4
        XCTAssertEqual(Array(x[o2..<o2 + 4]), [0x9A, 0x11, 0x00, 0x00])
    }

    func testGeneralReport() {
        var payload = [UInt8](repeating: 0, count: 58)
        payload[0] = 8
        payload.replaceSubrange(52..<58, with: PC205.signature)
        var g = GeneralReport(payload: payload)
        XCTAssertTrue(g.signatureOK)
        PC205Codec.apply(PC205.defaultProfile(), to: &g, parts: .all)
        XCTAssertEqual(g.bytes[1] & 0x0F, 5)
        XCTAssertEqual(g.bytes[1] >> 4, 1)
        XCTAssertEqual(Array(g.bytes[4..<12]), [4, 7, 10, 14, 16, 0x90, 0x90, 0x90])
        XCTAssertEqual(Array(g.bytes[43..<48]), [1, 3, 2, 6, 5])
        XCTAssertEqual(g.bytes[20] >> 4, 3)
        XCTAssertTrue(g.signatureOK)
        XCTAssertEqual(g.stages[0].x, 1200)
        var p = Profile()
        PC205Codec.load(&p, from: g)
        XCTAssertEqual(p.effect, 2)
    }

    func testModeReport() {
        var m = ModeReport(payload: [1, 3, 3, 3, 2, 3, 1, 0])
        PC205Codec.apply(PC205.defaultProfile(), to: &m)
        m.setRateHz(1000, mode: 2)
        XCTAssertEqual(m.featureBytes, [8, 1, 3, 3, 4, 2, 3, 1, 0])
    }

    /// Generic layer: partial/older profiles are padded to what the device supports and survive JSON.
    func testProfileNormalizationAndJSON() throws {
        let caps = PC205.capabilities
        let p = Profile().normalized(caps, defaults: PC205.defaultProfile())
        XCTAssertEqual(p.buttons.count, caps.modes)
        XCTAssertTrue(p.buttons.allSatisfy { $0.count == caps.slots })
        XCTAssertEqual(p.macros.count, caps.macroCount)
        XCTAssertEqual(p.stages.count, caps.dpiStages)
        XCTAssertTrue(caps.hasButtons && caps.hasDPI && caps.hasLighting && caps.hasPolling && caps.hasMacros)
        let full = PC205.defaultProfile()
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(PC205Codec.matrixPayload(back), PC205Codec.matrixPayload(full))
    }

    /// Key capture / macro recording on the Mac and the PC205 vendor layout data.
    func testMacKeyCodesAndLayout() {
        XCTAssertEqual(HIDKey.fromMacKeyCode(0), 0x04)      // A
        XCTAssertEqual(HIDKey.fromMacKeyCode(105), HIDKey.f13)
        XCTAssertEqual(HIDKey.fromMacKeyCode(56), 0xE1)     // left shift
        XCTAssertEqual(HIDKey.modifierBit(0xE3), 0x08)
        let caps = PC205.capabilities
        XCTAssertEqual(caps.shownSlots, 8)
        XCTAssertEqual(caps.buttonHotspots[caps.extraSideSlot - 1]?.x, 46)
        XCTAssertEqual(caps.skinProbe, "main_nr.png")
    }
}
