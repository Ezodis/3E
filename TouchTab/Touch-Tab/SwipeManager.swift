import Cocoa
import os.log

class SwipeManager {
    private static let accVelXThreshold: Float = 0.07
    private static let pinchThreshold: Float = 0.015
    // TODO: figure out the real value of the delay.
    private static let appSwitcherUIDelay: Double = 0.2
    private static let forceClickStageThreshold: Int = 2
    // Fallback pressure threshold for when "Force Click and haptic feedback" is disabled in
    // System Settings. In that case nsEvent.stage never reaches 2, but a hard press still
    // drives nsEvent.pressure close to 1.0, so we detect it with this threshold instead.
    // 0.99 is chosen to be high enough to avoid accidental triggers from normal clicks
    // (which typically reach ~0.5–0.9) while still firing reliably on a firm Force-Touch press.
    private static let forcePressureThreshold: Float = 0.99

    private static var eventTap: CFMachPort? = nil
    private static var eventSource: CFRunLoopSource? = nil
    static var isRunning: Bool { eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    // Global NSEvent monitor for force-click pressure events. Pressure events are synthesized
    // by the system from raw trackpad HID data; using NSEvent.addGlobalMonitorForEvents gives
    // us proper NSEvent objects with correct stage and pressure fields, unlike converting from
    // a CGEvent tap which can silently return nil for these synthesized events.
    private static var pressureEventMonitor: Any? = nil
    // Event state.
    private static var accVelX: Float = 0
    private static var accPinchDistance: Float = 0
    private static var prevTouchPositions: [String: NSPoint] = [:]
    // Gesture state. Gesture may consists of multiple events.
    private static var startTime: Date? = nil
    // Force click state.
    private static var forceClickActive = false
    // Pinch state: prevents repeated copy/paste triggers within a single pinch gesture.
    private static var pinchFired = false

    //TODO: move it somewhere else?
    private static func listener(_ eventType: EventType) {
        switch eventType {
        case .startOrContinue(.left):
            AppSwitcher.cmdShiftTab()
        case .startOrContinue(.right):
            AppSwitcher.cmdTab()
        case .end:
            AppSwitcher.selectInAppSwitcher()
        case .pinchIn:
            AppSwitcher.cmdC()
        case .pinchOut:
            AppSwitcher.cmdV()
        case .forceClick:
            AppSwitcher.cmdBacktick()
        case .cmdForceClick:
            AppSwitcher.cmdShiftBacktick()
        }
    }

    static func start() {
        if eventTap != nil {
            // The combined host retries when macOS disables the tap. An
            // existing disabled tap must be re-enabled, not treated as running.
            CGEvent.tapEnable(tap: eventTap!, enable: true)
            return
        }
        debugPrint("SwipeManager start")
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: { proxy, type, cgEvent, userInfo in
                return SwipeManager.eventHandler(proxy: proxy, eventType: type, cgEvent: cgEvent, userInfo: userInfo)
            },
            userInfo: nil
        )
        if eventTap == nil {
            os_log("Gesture event tap unavailable", log: OSLog(subsystem: "ris58h.Touch-Tab", category: "Gestures"), type: .error)
            debugPrint("SwipeManager couldn't create event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        eventSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: eventTap!, enable: true)
        os_log("Gesture event tap enabled: %{public}d", log: OSLog(subsystem: "ris58h.Touch-Tab", category: "Gestures"), type: .info, isRunning ? 1 : 0)

        // Use a global NSEvent monitor for force-click pressure events. This delivers proper
        // NSEvent objects with correct stage and pressure fields, which is more reliable than
        // converting from a CGEvent tap (where NSEvent(cgEvent:) can silently return nil for
        // synthesized pressure events).
        pressureEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .pressure) { nsEvent in
            SwipeManager.pressureEventHandler(nsEvent)
        }
        if pressureEventMonitor == nil {
            debugPrint("SwipeManager couldn't create pressure event monitor")
        }
    }

    static func stop() {
        if startTime != nil { endGesture() }
        startTime = nil
        forceClickActive = false
        pinchFired = false
        clearEventState()
        if let monitor = pressureEventMonitor {
            NSEvent.removeMonitor(monitor)
            pressureEventMonitor = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
            CFMachPortInvalidate(tap)
            eventSource = nil
            eventTap = nil
        }
    }
    
    private static func eventHandler(proxy: CGEventTapProxy, eventType: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
        if eventType.rawValue == NSEvent.EventType.gesture.rawValue, let nsEvent = NSEvent(cgEvent: cgEvent) {
            touchEventHandler(nsEvent)
        } else if (eventType == .tapDisabledByUserInput || eventType == .tapDisabledByTimeout) {
            debugPrint("SwipeManager tap disabled", eventType.rawValue)
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private static func touchEventHandler(_ nsEvent: NSEvent) {
        // Trackpad only: four simultaneous Touch Bar piano notes must not
        // become an app-switch gesture when this engine is embedded in 3£.
        let touches = Set(nsEvent.allTouches().filter { $0.type == .indirect })

        // Sometimes there are empty touch events that we have to skip. There are no empty touch events if Mission Control or App Expose use 3-finger swipes though.
        if touches.isEmpty {
            return
        }
        let touchesCount = touches.allSatisfy({ $0.phase == .ended }) ? 0 : touches.count

        switch touchesCount {
        case 2: processTwoFingers()
        case 4: processThreeFingers(touches: touches)
        default: processOtherFingers(touchesCount: touchesCount)
        }
    }

    private static func processTwoFingers() {
        // Two fingers scrolling in App Switcher is OK but we shouldn't accumulate gesture velocity here.
        clearEventState()
    }

    private static func processThreeFingers(touches: Set<NSTouch>) {
        // Read pinch distance BEFORE horizontalSwipeVelocity updates prevTouchPositions.
        let pinchDistance = detectPinch(touches: touches)

        // Check for horizontal swipe (also updates prevTouchPositions).
        let velX = SwipeManager.horizontalSwipeVelocity(touches: touches)

        // Horizontal swipe takes priority over pinch. When a swipe is in progress, any
        // minor convergence/divergence of fingers should not be mistaken for a pinch.
        if let velX = velX {
            accPinchDistance = 0

            accVelX += velX
            // Not enough swiping.
            if abs(accVelX) < accVelXThreshold {
                return
            }

            if startTime == nil {
                startTime = Date()
            } else {
                let interval = startTime!.timeIntervalSinceNow
                if -interval < appSwitcherUIDelay {
                    // We skip subsequent events until App Switcher UI is shown.
                    clearEventState()
                    return
                }
            }

            startOrContinueGesture()
            clearEventState()
            return
        }

        // No horizontal swipe — check for pinch gesture.
        if let distance = pinchDistance {
            accPinchDistance += distance

            if !pinchFired && abs(accPinchDistance) >= pinchThreshold {
                pinchFired = true
                if accPinchDistance > 0 {
                    listener(.pinchOut)
                } else {
                    listener(.pinchIn)
                }
                clearEventState()
            }
        }
    }

    private static func processOtherFingers(touchesCount: Int) {
        if startTime != nil {
            endGesture()
            clearEventState()
            startTime = nil
        }
        if touchesCount == 0 {
            pinchFired = false
        }
    }

    private static func pressureEventHandler(_ nsEvent: NSEvent) {
        // When "Force Click and haptic feedback" is disabled in System Settings, macOS no
        // longer advances nsEvent.stage to 2, so we also check the raw pressure value as a
        // fallback. This lets the app react to a hard press without the system Quick Look
        // feature being enabled.
        let isForcePress = nsEvent.stage >= forceClickStageThreshold
            || nsEvent.pressure >= forcePressureThreshold
        if isForcePress && !forceClickActive {
            forceClickActive = true
            if nsEvent.modifierFlags.contains(.command) {
                listener(.cmdForceClick)
            } else {
                listener(.forceClick)
            }
        } else if !isForcePress {
            forceClickActive = false
        }
    }

    private static func clearEventState() {
        accVelX = 0
        accPinchDistance = 0
        prevTouchPositions.removeAll()
    }

    private static func startOrContinueGesture() {
        let direction: EventType.Direction = accVelX < 0 ? .left : .right
        listener(.startOrContinue(direction: direction))
    }

    private static func endGesture() {
        listener(.end)
    }

    private static func detectPinch(touches: Set<NSTouch>) -> Float? {
        // We need at least 2 touches to calculate distance
        guard touches.count >= 2 else {
            return nil
        }
        
        // Calculate centroid (center point) of all touches
        var currentCentroid = NSPoint.zero
        var previousCentroid = NSPoint.zero
        var validPreviousCount = 0
        
        for touch in touches {
            currentCentroid.x += touch.normalizedPosition.x
            currentCentroid.y += touch.normalizedPosition.y
            
            if let prevPos = prevTouchPositions["\(touch.identity)"] {
                previousCentroid.x += prevPos.x
                previousCentroid.y += prevPos.y
                validPreviousCount += 1
            }
        }
        
        // We need previous positions to calculate pinch
        guard validPreviousCount >= 2 else {
            return nil
        }
        
        currentCentroid.x /= CGFloat(touches.count)
        currentCentroid.y /= CGFloat(touches.count)
        previousCentroid.x /= CGFloat(validPreviousCount)
        previousCentroid.y /= CGFloat(validPreviousCount)
        
        // Calculate average distance from centroid for current and previous positions
        var currentAvgDistance: Float = 0
        var previousAvgDistance: Float = 0
        
        for touch in touches {
            let currentPos = touch.normalizedPosition
            let dx = currentPos.x - currentCentroid.x
            let dy = currentPos.y - currentCentroid.y
            currentAvgDistance += Float(sqrt(dx * dx + dy * dy))
            
            if let prevPos = prevTouchPositions["\(touch.identity)"] {
                let pdx = prevPos.x - previousCentroid.x
                let pdy = prevPos.y - previousCentroid.y
                previousAvgDistance += Float(sqrt(pdx * pdx + pdy * pdy))
            }
        }
        
        currentAvgDistance /= Float(touches.count)
        previousAvgDistance /= Float(validPreviousCount)
        
        // Positive value means pinch out (fingers moving apart)
        // Negative value means pinch in (fingers moving together)
        return currentAvgDistance - previousAvgDistance
    }

    private static func horizontalSwipeVelocity(touches: Set<NSTouch>) -> Float? {
        var allRight = true
        var allLeft = true
        var sumVelX = Float(0)
        var sumVelY = Float(0)
        for touch in touches {
            let (velX, velY) = touchVelocity(touch)
            allRight = allRight && velX >= 0
            allLeft = allLeft && velX <= 0
            sumVelX += velX
            sumVelY += velY

            if touch.phase == .ended {
                prevTouchPositions.removeValue(forKey: "\(touch.identity)")
            } else {
                prevTouchPositions["\(touch.identity)"] = touch.normalizedPosition
            }
        }
        // All fingers should move in the same direction.
        if !allRight && !allLeft {
            return nil
        }

        let velX = sumVelX / Float(touches.count)
        let velY = sumVelY / Float(touches.count)
        // Only horizontal swipes are interesting.
        if abs(velX) <= abs(velY) {
            return nil
        }

        return velX
    }
    
    private static func touchVelocity(_ touch: NSTouch) -> (Float, Float) {
        guard let prevPosition = prevTouchPositions["\(touch.identity)"] else {
            return (0, 0)
        }
        let position = touch.normalizedPosition
        return (Float(position.x - prevPosition.x), Float(position.y - prevPosition.y))
    }

    enum EventType {
        case startOrContinue(direction: Direction)
        case end
        case pinchIn
        case pinchOut
        case forceClick
        case cmdForceClick

        enum Direction {
            case left
            case right
        }
    }
}
