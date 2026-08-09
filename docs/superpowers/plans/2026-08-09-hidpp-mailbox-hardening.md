# HID++ Mailbox Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the two residual HID++ races — concurrent `request()` calls stealing each other's replies, and single-slot mailbox dropping overwritten reports — by extracting a testable `HIDReportMailbox` with exclusive request ownership and a FIFO report queue.

**Architecture:** A new Foundation-only `HIDReportMailbox` (NSCondition + FIFO `[[UInt8]]`, drop-oldest beyond `capacity`) owns the report queue, the reader gate (`activeRequests`), and exclusive request ownership (`beginRequest` waits until the previous request releases). `IOHIDDeviceWrapper` and the test `MockHIDDevice` both delegate to it, so production and tests share the exact same primitives.

**Tech Stack:** Swift, Swift Package Manager, XCTest. No IOKit in the mailbox (Foundation only).

## Global Constraints

- `HIDDevice` protocol signatures (`read`, `readForRequest`, `beginRequest`, `endRequest`, `write`, `close`, `productName`) are **unchanged**.
- `beginRequest()` is **exclusive**: waits until `activeRequests == 0`, then sets it to `1`; `endRequest()` sets it back to `0`.
- `read(timeout:)` (monitor loop) must **not consume** while `activeRequests > 0`; it waits until the gate clears and a report exists, or returns `nil` on timeout.
- `readForRequest(timeout:)` ignores the gate (request path).
- Overflow policy: **drop-oldest** (remove the oldest report first when at capacity).
- `capacity = 16` in `IOHIDDeviceWrapper`; the mock uses `capacity = 64` so seeded test reports are never dropped.
- `HIDReportMailbox` must be testable without hardware (Foundation + XCTest only).
- Full test suite stays green; `swift build` stays warning-free.

---

### Task 1: `HIDReportMailbox` + unit tests (TDD)

**Files:**
- Create: `Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift`
- Test: `Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift`

**Interfaces:**
- Produces (consumed by Tasks 2–4):
  - `final class HIDReportMailbox` (internal)
  - `init(capacity: Int = 16)`
  - `func enqueue(_ bytes: [UInt8])`
  - `func read(timeout: TimeInterval) -> [UInt8]?`
  - `func readForRequest(timeout: TimeInterval) -> [UInt8]?`
  - `func beginRequest()`
  - `func endRequest()`
  - `func snapshot() -> [[UInt8]]` (test-support getter)
  - `func replaceAll(_ reports: [[UInt8]])` (test-support seeding)

- [ ] **Step 1: Write the failing test file**

Create `Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift`:

```swift
import XCTest
@testable import RatTamerCore

final class HIDReportMailboxTests: XCTestCase {
    func testFifoOrder() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.enqueue([1])
        mailbox.enqueue([2])
        mailbox.enqueue([3])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [1])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [2])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [3])
    }

    func testCapacityDropsOldest() {
        let mailbox = HIDReportMailbox(capacity: 2)
        mailbox.enqueue([1])
        mailbox.enqueue([2])
        mailbox.enqueue([3])
        XCTAssertEqual(mailbox.snapshot(), [[2], [3]])
    }

    func testReadIsGatedWhileRequestInFlight() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        mailbox.enqueue([1])
        XCTAssertNil(mailbox.read(timeout: 0))
        mailbox.endRequest()
        XCTAssertEqual(mailbox.read(timeout: 0), [1])
    }

    func testReadForRequestIgnoresGate() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        mailbox.enqueue([1])
        XCTAssertEqual(mailbox.readForRequest(timeout: 0), [1])
        mailbox.endRequest()
    }

    func testReadForRequestTimesOutWhenEmpty() {
        let mailbox = HIDReportMailbox(capacity: 16)
        XCTAssertNil(mailbox.readForRequest(timeout: 0.05))
    }

    func testBeginRequestIsExclusive() {
        let mailbox = HIDReportMailbox(capacity: 16)
        mailbox.beginRequest()
        let exp = expectation(description: "second owner waits")
        DispatchQueue.global().async {
            mailbox.beginRequest()
            exp.fulfill()
        }
        usleep(50_000)
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 0.1), .timedOut)
        mailbox.endRequest()
        wait(for: [exp], timeout: 1.0)
        mailbox.endRequest()
    }

    func testConcurrentProducerConsumerDeliversAll() {
        let mailbox = HIDReportMailbox(capacity: 16)
        let count = 8
        let producer = DispatchQueue(label: "test.hidpp.producer")
        producer.async {
            for i in 0..<count {
                mailbox.enqueue([UInt8(i)])
            }
        }
        var received = 0
        for _ in 0..<count {
            if mailbox.readForRequest(timeout: 1.0) != nil {
                received += 1
            }
        }
        XCTAssertEqual(received, count)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HIDReportMailboxTests`
Expected: FAIL — "cannot find 'HIDReportMailbox' in scope"

- [ ] **Step 3: Write the mailbox implementation**

Create `Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift`:

```swift
import Foundation

/// Thread-safe FIFO report mailbox with request-ownership semantics.
///
/// The monitor loop reads via `read(timeout:)`, which refuses to consume while
/// a synchronous request is in flight (`activeRequests > 0`) so the loop cannot
/// steal a request's reply. Requests read via `readForRequest(timeout:)`,
/// which ignores the gate. `beginRequest()` is exclusive — it waits until no
/// other request holds ownership — so two concurrent requests can never steal
/// each other's replies. Reports beyond `capacity` drop the oldest entry.
final class HIDReportMailbox {
    private let condition = NSCondition()
    private var reports: [[UInt8]] = []
    private var activeRequests = 0
    private let capacity: Int

    init(capacity: Int = 16) {
        self.capacity = capacity
    }

    func enqueue(_ bytes: [UInt8]) {
        condition.lock()
        if reports.count >= capacity {
            reports.removeFirst()
        }
        reports.append(bytes)
        condition.broadcast()
        condition.unlock()
    }

    func read(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if activeRequests == 0, !reports.isEmpty {
                return reports.removeFirst()
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    func readForRequest(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if !reports.isEmpty {
                return reports.removeFirst()
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }

    func beginRequest() {
        condition.lock()
        while activeRequests > 0 {
            condition.wait()
        }
        activeRequests = 1
        condition.broadcast()
        condition.unlock()
    }

    func endRequest() {
        condition.lock()
        activeRequests = 0
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> [[UInt8]] {
        condition.lock()
        defer { condition.unlock() }
        return reports
    }

    func replaceAll(_ newReports: [[UInt8]]) {
        condition.lock()
        reports = Array(newReports.suffix(capacity))
        condition.broadcast()
        condition.unlock()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HIDReportMailboxTests`
Expected: PASS — all 7 tests

- [ ] **Step 5: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift
git commit -m "feat(hidpp): HIDReportMailbox with FIFO queue and exclusive requests"
```

---

### Task 2: `IOHIDDeviceWrapper` delegates to the mailbox

**Files:**
- Modify: `Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift`
- Modify: `Sources/RatTamerCore/HIDPP/HIDDevice.swift` (doc comments only)

**Interfaces:**
- Consumes: `HIDReportMailbox` from Task 1.
- Produces: `IOHIDDeviceWrapper` whose `read`, `readForRequest`, `beginRequest`, `endRequest` and the input-report callback all delegate to `HIDReportMailbox`; `HIDDevice` protocol doc comments describing the new semantics.

- [ ] **Step 1: Remove the mailbox state from the wrapper**

In `IOHIDDeviceWrapper.swift`, replace the state block (currently lines 7–9):

```swift
    private let condition = NSCondition()
    private var mailbox: [UInt8]?
    private var inFlightRequests = 0
```

with:

```swift
    private let mailbox = HIDReportMailbox(capacity: 16)
```

- [ ] **Step 2: Delegate the read methods**

Replace the bodies of `read(timeout:)`, `readForRequest(timeout:)`, `beginRequest()` and `endRequest()` (currently lines 74–116) with:

```swift
    public func read(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.read(timeout: timeout)
    }

    public func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.readForRequest(timeout: timeout)
    }

    public func beginRequest() {
        mailbox.beginRequest()
    }

    public func endRequest() {
        mailbox.endRequest()
    }
```

- [ ] **Step 3: Delegate enqueue**

Replace the `enqueue(_:)` body (currently lines 118–123) with:

```swift
    private func enqueue(_ bytes: [UInt8]) {
        mailbox.enqueue(bytes)
    }
```

- [ ] **Step 4: Update the protocol doc comments**

In `HIDDevice.swift`, update the doc comments on `readForRequest`, `beginRequest` and `endRequest` (currently lines 7–15) to:

```swift
    /// Reads a report from the FIFO mailbox without consulting the in-flight
    /// request gate. Used by `HIDPPSession.request` so a pending synchronous
    /// request never blocks on its own gate.
    func readForRequest(timeout: TimeInterval) throws -> [UInt8]?
    /// Marks the start of a synchronous feature request. **Exclusive**: waits
    /// until no other request is in flight, so concurrent requests cannot steal
    /// each other's replies. While a request is in flight, `read(timeout:)`
    /// must not consume reports so the monitor loop cannot steal its reply.
    func beginRequest()
    /// Marks the end of a synchronous feature request, releasing ownership so
    /// the next queued request (or the gated monitor loop) can proceed.
    func endRequest()
```

- [ ] **Step 5: Build and run the full suite**

Run: `swift build` then `swift test`
Expected: BUILD SUCCEEDED, all 302 tests pass (295 original + 7 mailbox tests; the mock still has its own queue — unaffected).

- [ ] **Step 6: Commit**

```bash
git add Sources/RatTamerCore/HIDPP/IOHIDDeviceWrapper.swift Sources/RatTamerCore/HIDPP/HIDDevice.swift
git commit -m "refactor(hidpp): IOHIDDeviceWrapper delegates to HIDReportMailbox"
```

---

### Task 3: `MockHIDDevice` uses the real mailbox

**Files:**
- Modify: `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift`
- Modify: `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift` (obsolete test)

**Interfaces:**
- Consumes: `HIDReportMailbox` from Task 1 (incl. `snapshot`/`replaceAll`).
- Produces: `MockHIDDevice` exposing the same property surface as today — `writeLog`, `queuedReads` (now a computed property seeding the mailbox), `onWrite`, `onRemoved`, `productName`, `closeCalled`, `closeCount` — but delegating queue + gate to the real `HIDReportMailbox`.

- [ ] **Step 1: Rewrite `MockHIDDevice`**

Replace the whole body of `Tests/RatTamerCoreTests/Support/MockHIDDevice.swift` with:

```swift
import Foundation
@testable import RatTamerCore

final class MockHIDDevice: HIDDevice {
    var writeLog: [[UInt8]] = []
    private let mailbox = HIDReportMailbox(capacity: 64)
    var onWrite: (([UInt8]) -> [UInt8]?)?
    var onRemoved: (() -> Void)?
    var productName: String?
    private(set) var closeCalled = false
    private(set) var closeCount = 0

    /// Mirrors the real wrapper: seeded reports go through the exact same
    /// FIFO mailbox the production wrapper uses.
    var queuedReads: [[UInt8]] {
        get { mailbox.snapshot() }
        set { mailbox.replaceAll(newValue) }
    }

    func close() {
        closeCalled = true
        closeCount += 1
    }

    func write(_ bytes: [UInt8]) throws {
        writeLog.append(bytes)
        if let response = onWrite?(bytes) {
            mailbox.enqueue(response)
        }
    }

    func read(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.read(timeout: timeout)
    }

    func readForRequest(timeout: TimeInterval) throws -> [UInt8]? {
        mailbox.readForRequest(timeout: timeout)
    }

    func beginRequest() {
        mailbox.beginRequest()
    }

    func endRequest() {
        mailbox.endRequest()
    }
}
```

- [ ] **Step 2: Replace the obsolete ping test**

`testPingSucceedsWhileARequestIsInFlight` in `HIDPPSessionTests.swift` (lines 92–99) sets `mock.inFlightRequests = 1`, which no longer exists. Under exclusive requests, a ping issued while another request holds ownership now *waits* for it (bounded by the owner's timeout) instead of racing — a property covered by the exclusive-ownership mailbox test (Task 1) and the new concurrency test (Task 4). Replace the test with:

```swift
    func testPingSerializesWithRequests() throws {
        let mock = MockHIDDevice()
        mock.onWrite = { _ in [0x10, 0x01, 0x00, 0x01, 0x00] }
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 1)
        XCTAssertTrue(answered)
    }
```

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: all tests pass (295 + 7 new mailbox tests = 302). The session/service suites (battery, DPI, smart-shift, reprogrammable controls, hi-res wheel, device name) exercise the real mailbox through the mock.

- [ ] **Step 4: Commit**

```bash
git add Tests/RatTamerCoreTests/Support/MockHIDDevice.swift Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift
git commit -m "refactor(tests): MockHIDDevice uses the real HIDReportMailbox"
```

---

### Task 4: Concurrency regression test (no reply stealing)

**Files:**
- Modify: `Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift`

**Interfaces:**
- Consumes: `HIDPPSession.request`, `MockHIDDevice` (Task 3).
- Produces: a regression guard proving two concurrent `request()` calls each receive their own reply.

- [ ] **Step 1: Write the failing-for-the-old-design test**

Append to `HIDPPSessionTests.swift`:

```swift
    func testConcurrentRequestsDoNotStealReplies() throws {
        let mock = MockHIDDevice()
        let session = HIDPPSession(device: mock)
        mock.onWrite = { bytes in
            bytes[2] == 0x0A
                ? [0x11, 0x01, 0x0A, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00]
                : [0x11, 0x01, 0x0B, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00]
        }

        let group = DispatchGroup()
        let resultsLock = NSLock()
        var results: [UInt8] = []
        let queue = DispatchQueue(label: "test.hidpp.concurrent", attributes: .concurrent)

        for feature in [0x0A, 0x0B] {
            group.enter()
            queue.async {
                defer { group.leave() }
                if let resp = try? session.request(
                    deviceIndex: 1, featureIndex: UInt8(feature), functionID: 0x03, timeout: 1.0
                ), resp.count > 2 {
                    resultsLock.lock()
                    results.append(resp[2])
                    resultsLock.unlock()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(results.sorted(), [0x0A, 0x0B])
    }
```

Note: under the old non-exclusive mailbox this test races on the mock's queue (data race on `queuedReads`) and can lose a reply; under exclusive ownership it is deterministic. It is a regression guard, not a red→green unit test — Task 1 already covered exclusivity at the mailbox level with true TDD.

- [ ] **Step 2: Run it repeatedly to check for flakiness**

Run: `swift test --filter HIDPPSessionTests/testConcurrentRequestsDoNotStealReplies` (repeat 5×)
Expected: PASS every time.

- [ ] **Step 3: Run the full suite and build**

Run: `swift test` then `swift build`
Expected: all tests pass; build succeeds with no warnings.

- [ ] **Step 4: Commit**

```bash
git add Tests/RatTamerCoreTests/HIDPP/HIDPPSessionTests.swift
git commit -m "test(hidpp): concurrent requests do not steal replies"
```

---

### Task 5: Validation and docs

**Files:**
- Modify: `docs/TECHNICAL.md` (if it describes the HID++ read path)

**Interfaces:**
- Consumes: everything from Tasks 1–4.

- [ ] **Step 1: Check `docs/TECHNICAL.md`**

Read `docs/TECHNICAL.md` and, if it describes the HID++ mailbox / request read path, update it to mention the FIFO mailbox and exclusive requests. If it does not cover the read path, leave it untouched.

- [ ] **Step 2: Final validation**

Run: `swift test` and `swift build`
Expected: all 303 tests pass; build clean.

- [ ] **Step 3: Commit**

```bash
git add docs/TECHNICAL.md
git commit -m "docs: describe FIFO mailbox and exclusive HID++ requests"
```

(If Step 1 made no changes, skip the commit.)
