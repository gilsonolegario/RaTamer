import Foundation
import IOKit.hid

public final class IOHIDDeviceWrapper: HIDDevice {
    public let productName: String?
    private let device: IOHIDDevice
    private let mailbox = HIDReportMailbox(capacity: 16)
    private var buffer = [UInt8](repeating: 0, count: 64)
    private var readThread: Thread!
    private var runLoop: CFRunLoop!
    private let threadExited = DispatchSemaphore(value: 0)
    private var isClosed = false

    public init(device: IOHIDDevice) {
        self.device = device
        self.productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        self.readThread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            IOHIDDeviceScheduleWithRunLoop(self.device, self.runLoop,
                                           CFRunLoopMode.defaultMode.rawValue)
            guard !self.isClosed else {
                IOHIDDeviceUnscheduleFromRunLoop(self.device, self.runLoop,
                                                 CFRunLoopMode.defaultMode.rawValue)
                self.threadExited.signal()
                return
            }
            CFRunLoopRun()
            IOHIDDeviceUnscheduleFromRunLoop(self.device, self.runLoop,
                                             CFRunLoopMode.defaultMode.rawValue)
            self.threadExited.signal()
        }
        self.readThread.name = "RaTamer.HIDRead"
        self.readThread.start()
        self.buffer.withUnsafeMutableBufferPointer { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device, baseAddress, bufferPtr.count, { context, _, _, _, _, report, length in
                    guard let context else { return }
                    let wrapper = Unmanaged<IOHIDDeviceWrapper>.fromOpaque(context).takeUnretainedValue()
                    wrapper.enqueueReport(report, length: length)
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
        _ = threadExited.wait(timeout: .now() + 5)
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
