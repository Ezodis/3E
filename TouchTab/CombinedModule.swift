import Cocoa

// Loaded into 3£ itself, never into its MIDI/App-picker helper processes.
// Shares the exact gesture implementation with the standalone TouchTab build.
@objc(ThreeEGestures)
public final class ThreeEGestures: NSObject {
    @objc public static func start() -> Bool {
        SwipeManager.start()
        return SwipeManager.isRunning
    }
    @objc public static func stop() { SwipeManager.stop() }
    @objc public static func running() -> Bool { SwipeManager.isRunning }
}
