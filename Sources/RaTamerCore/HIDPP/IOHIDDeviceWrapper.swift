import Foundation
import IOKit.hid

public final class IOHIDDeviceWrapper: HIDDevice {
    public let productName: String?
    private let device: IOHIDDevice
    private let mailbox = HIDReportMailbox(capacity: 16)
    /// Stable, heap-allocated report buffer. A Swift `[UInt8]` array may relocate
    /// its storage (copy-on-write) and leave the IOKit callback pointing at
    /// freed memory; an explicit allocation stays put for the wrapper's life.
    private let reportBufferSize = 64
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var readThread: Thread!
    private var runLoop: CFRunLoop?
    private let threadExited = DispatchSemaphore(value: 0)
    /// Serialises access to `isClosed`/`runLoop` across the read thread and the
    /// callers of `close()`, and guarantees `close()` only stops a run loop the
    /// thread has actually published (`runLoopReady`) — so `CFRunLoopRun` can
    /// never outlive the thread and become a zombie.
    private let lock = NSLock()
    private let runLoopReady = DispatchSemaphore(value: 0)
    private var isClosed = false

    public init(device: IOHIDDevice) {
        self.device = device
        self.productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
        reportBuffer!.initialize(repeating: 0, count: reportBufferSize)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer!, reportBufferSize, { context, _, _, _, _, report, length in
                guard let context else { return }
                let wrapper = Unmanaged<IOHIDDeviceWrapper>.fromOpaque(context).takeUnretainedValue()
                wrapper.enqueueReport(report, length: length)
            }, context)
        self.readThread = Thread { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.runLoop = CFRunLoopGetCurrent()
            let closed = self.isClosed
            self.lock.unlock()
            self.runLoopReady.signal()
            IOHIDDeviceScheduleWithRunLoop(self.device, self.runLoop!,
                                           CFRunLoopMode.defaultMode.rawValue)
            guard !closed else {
                IOHIDDeviceUnscheduleFromRunLoop(self.device, self.runLoop!,
                                                 CFRunLoopMode.defaultMode.rawValue)
                self.threadExited.signal()
                return
            }
            CFRunLoopRun()
            IOHIDDeviceUnscheduleFromRunLoop(self.device, self.runLoop!,
                                             CFRunLoopMode.defaultMode.rawValue)
            self.threadExited.signal()
        }
        self.readThread.name = "RaTamer.HIDRead"
        self.readThread.start()
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
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        lock.unlock()

        // Wait for the read thread to publish its run loop before stopping it,
        // so we never call CFRunLoopStop(nil) and strand CFRunLoopRun.
        _ = runLoopReady.wait(timeout: .now() + 5)
        lock.lock()
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        lock.unlock()

        // Closing the handle unregisters the input report callback.
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        _ = threadExited.wait(timeout: .now() + 5)

        if let reportBuffer {
            reportBuffer.deallocate()
            self.reportBuffer = nil
        }
    }

    public func read(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.read(timeout: timeout)
    }

    public func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.readForRequest(timeout: timeout)
    }

    public func beginRequest() {
        mailbox.beginRequest()
    }

    public func beginRequest(timeout: TimeInterval) -> Bool {
        mailbox.beginRequest(timeout: timeout)
    }

    public func endRequest() {
        mailbox.endRequest()
    }

    public func wake() {
        mailbox.wake()
    }

    public func recycle(_ bytes: inout [UInt8]) {
        mailbox.recycle(&bytes)
    }

    private func enqueueReport(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
        var buffer = mailbox.takeBuffer()
        buffer.append(contentsOf: UnsafeBufferPointer(start: report, count: length))
        mailbox.enqueue(buffer)
    }
}
