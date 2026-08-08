import Foundation
import IOKit.hid

public final class IOHIDDeviceWrapper: HIDDevice {
    private let device: IOHIDDevice
    private let condition = NSCondition()
    private var mailbox: [UInt8]?
    private var inFlightRequests = 0
    private var buffer = [UInt8](repeating: 0, count: 64)
    private var readThread: Thread!
    private var runLoop: CFRunLoop!
    private let threadExited = DispatchSemaphore(value: 0)
    private var isClosed = false

    public init(device: IOHIDDevice) {
        self.device = device
        self.readThread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(self.device, self.runLoop,
                                           CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopRun()
            IOHIDDeviceUnscheduleFromRunLoop(self.device, self.runLoop,
                                             CFRunLoopMode.defaultMode.rawValue)
            self.threadExited.signal()
        }
        self.readThread.name = "RatTamer.HIDRead"
        self.readThread.start()
        self.buffer.withUnsafeMutableBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device, baseAddress, bufferPtr.count, { context, _, _, _, _, report, length in
                    guard let context else { return }
                    let wrapper = Unmanaged<IOHIDDeviceWrapper>.fromOpaque(context).takeUnretainedValue()
                    let bytes = Array(UnsafeRawBufferPointer(start: report, count: length))
                    wrapper.enqueue(bytes)
                }, context)
        }
    }

    deinit {
        close()
    }

    public var isOpen: Bool { true }

    public func write(_ bytes: [UInt8]) throws {
        let result = bytes.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput,
                                 Int(buf[0]), buf.baseAddress!, buf.count)
        }
        guard result == kIOReturnSuccess else {
            throw HIDLocatorError.openFailed("write failed: \(result)")
        }
    }

    /// Unregisters the callback, stops the read loop and closes the IOKit
    /// handle. Idempotent; the read thread is joined so no zombie survives a
    /// reconnect.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        // Closing the handle unregisters the input report callback.
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        threadExited.wait()
    }

    public func read(timeout: TimeInterval) throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if inFlightRequests > 0 {
                if !condition.wait(until: deadline) { return nil }
                continue
            }
            if let pending = mailbox {
                mailbox = nil
                return pending
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    public func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let pending = mailbox {
                mailbox = nil
                return pending
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    public func beginRequest() {
        condition.lock()
        inFlightRequests += 1
        condition.broadcast()
        condition.unlock()
    }

    public func endRequest() {
        condition.lock()
        inFlightRequests -= 1
        condition.broadcast()
        condition.unlock()
    }

    private func enqueue(_ bytes: [UInt8]) {
        condition.lock()
        mailbox = bytes
        condition.broadcast()
        condition.unlock()
    }
}
