# HID++ mailbox hardening (serialized requests + FIFO mailbox)

Date: 2026-08-09
Status: Approved

## Goal

Eliminate the two residual races documented in the 0.9.0 release-prep plan:

1. **Reply stealing** — two concurrent `HIDPPSession.request()` calls on the same
   device consume each other's replies from the single-slot mailbox. The reply
   matcher in `request()` discards a reply it does not own (it was already
   consumed), so the loser times out (`noResponse` / nil) even though the device
   answered correctly.
2. **Report drops** — the single-slot mailbox (`mailbox: [UInt8]?`) overwrites a
   pending report when a new one arrives (`enqueue` replaces the slot). A reply
   or event can be silently lost.

Secondary goal: make the mailbox logic unit-testable without hardware. Today it
lives inline in `IOHIDDeviceWrapper`, which requires a real `IOHIDDevice` to
instantiate, so the concurrency semantics are only mirrored (imperfectly) by
`MockHIDDevice`. That divergence is the class of bug that caused the stale-binary
debugging session — the mock must exercise the exact same primitives as production.

## Design

### 1. New `HIDReportMailbox` (RatTamerCore, Foundation only)

File: `Sources/RatTamerCore/HIDPP/HIDReportMailbox.swift`. No IOKit dependency.

A thread-safe FIFO report queue with request-ownership semantics, built on
`NSCondition`:

- **State:** `reports: [[UInt8]]` (FIFO), `capacity: Int = 16`,
  `activeRequests: Int` (the reader gate, 0 or 1).
- `enqueue(_ bytes: [UInt8])` — appends a report; when `reports.count >= capacity`
  removes the oldest first (drop-oldest). Broadcasts.
- `read(timeout:)` — waits until `activeRequests == 0` **and** a report exists;
  returns the head report or `nil` on timeout. This is the monitor-loop path.
- `readForRequest(timeout:)` — waits until a report exists (ignores the gate);
  returns the head report or `nil` on timeout. This is the request path.
- `beginRequest()` — **exclusive**: waits until `activeRequests == 0`, then sets
  `activeRequests = 1`. Broadcasts.
- `endRequest()` — sets `activeRequests = 0`, broadcasts.

Exclusive `beginRequest` serializes requests device-wide: only one
request/reply exchange is in flight at a time, so no two requesters can steal
each other's replies. The gate in `read` (monitor loop) still prevents the loop
from consuming a request's reply; with exclusivity the gate also keeps events
from piling into the request path.

### 2. `IOHIDDeviceWrapper` refactor

- Remove `condition`, `mailbox`, `inFlightRequests`; add `mailbox =
  HIDReportMailbox(capacity: 16)`.
- `read(timeout:)`, `readForRequest(timeout:)`, `beginRequest()`, `endRequest()`
  delegate to the mailbox.
- The input-report callback (`enqueue`) delegates to `mailbox.enqueue`.
- `close()`, the read thread, `write(_:)`, `productName` unchanged.

### 3. `MockHIDDevice` refactor

- Use the real `HIDReportMailbox` internally for its queue + gate, mirroring the
  wrapper exactly (`read`/`readForRequest`/`beginRequest`/`endRequest` delegate).
- Keep the test-support surface the existing suites rely on: `writeLog`,
  `onWrite` (writes → queued reply), `onRemoved`, `productName`, `closeCalled`,
  `closeCount`.
- Rationale: session-level tests (battery, DPI, smart-shift, etc.) then exercise
  the exact production primitives, closing the mock-vs-real divergence.

### 4. Protocol

`HIDDevice` signatures are unchanged (`read`, `readForRequest`, `beginRequest`,
`endRequest`, `write`, `close`, `productName`). Update the doc comments to
describe the new semantics: `beginRequest` is exclusive; `read` refuses to
consume while a request is in flight.

### 5. Tests

New `Tests/RatTamerCoreTests/HIDPP/HIDReportMailboxTests.swift`:

1. FIFO order — `enqueue` A, B, C → `readForRequest` returns A, B, C.
2. Capacity / drop-oldest — enqueue `capacity + 1` reports → oldest dropped,
   newest `capacity` retained.
3. Gate — during `beginRequest`, `read(timeout: small)` returns `nil` without
   consuming; after `endRequest`, the queued report is readable.
4. Exclusive ownership — thread 1 `beginRequest`; thread 2 `beginRequest` blocks
   until thread 1 `endRequest`, then proceeds.
5. Timeout — `readForRequest` on an empty mailbox returns `nil` after timeout.
6. Concurrent producer/consumer — background thread enqueues N reports while
   `readForRequest` consumes them; all N delivered, none lost.

New session concurrency test (e.g. `HIDPPSessionTests` or
`HIDReportMailboxTests`): two threads issue `request()` for distinct
features/replies via a `MockHIDDevice` with per-write distinct replies; each
thread receives its own reply (no steal).

Full suite must stay green.

### 6. Error handling / edge cases

- `capacity = 16` bounds memory to ≤ 1 KB (reports are ≤ 64 bytes).
- A request holds exclusive ownership for at most its own `timeout` (0.5 s);
  a waiter is therefore delayed by at most ~0.5 s before acquiring ownership.
  No new timeout is needed at the mailbox level.
- `drain(_:)` and `ping()` are unchanged in behavior; `ping()` benefits from the
  same exclusivity automatically (it uses `beginRequest`/`endRequest`).

## Out of scope

- Notarization, CI/CD, profiles UI, device-picker onboarding (separate roadmap
  items).
- Detecting and auto-retrying a dropped reply at the protocol layer — the FIFO
  buffer plus the existing `request()` retry loop in callers is sufficient for
  now.
