import CoreGraphics
import Foundation
import os

public final class ScrollWheelTap {
    public typealias Direction = ThumbWheel.Direction

    private static let log = Logger(subsystem: "com.rattamer", category: "thumbwheel")

    private let shouldIntercept: (Direction) -> Bool
    private let onNotch: (Direction) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accumulator = ThumbWheel.NotchAccumulator()

    public init(shouldIntercept: @escaping (Direction) -> Bool,
                onNotch: @escaping (Direction) -> Void) {
        self.shouldIntercept = shouldIntercept
        self.onNotch = onNotch
    }

    public var isActive: Bool { tap != nil }

    public func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handle,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("tapCreate failed (Accessibility not granted?)")
            return
        }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        Self.log.info("scroll wheel tap started")
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        accumulator.reset()
        Self.log.info("scroll wheel tap stopped")
    }

    func process(deltaX: Int64, deltaY: Int64, isContinuous: Int64,
                 phase: Int64, pointDeltaX: Int64) -> Bool {
        guard ThumbWheel.isThumbWheel(deltaX: deltaX, deltaY: deltaY,
                                      isContinuous: isContinuous, phase: phase) else {
            return false
        }
        let direction = ThumbWheel.direction(forDeltaX: deltaX)
        guard shouldIntercept(direction) else { return false }
        let notches = accumulator.push(pixels: pointDeltaX, direction: direction)
        for _ in 0..<notches {
            onNotch(direction)
        }
        return true
    }

    private static let handle: CGEventTapCallBack = { _, _, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<ScrollWheelTap>.fromOpaque(refcon).takeUnretainedValue()
        let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let pointDeltaX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let suppress = tap.process(deltaX: deltaX, deltaY: deltaY,
                                   isContinuous: isContinuous, phase: phase,
                                   pointDeltaX: pointDeltaX)
        return suppress ? nil : Unmanaged.passUnretained(event)
    }
}
