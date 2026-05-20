# Swift 6 / Observation / swift-clocks Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `SwiftyOTP` from Combine + `Foundation.Timer` + XCTest to a strict-Swift-6, `@MainActor @Observable` `OTPTimer` driven by a `Sendable` `Countdown` over `swift-clocks`, with all tests on swift-testing — without ever leaving the test suite red.

**Architecture:** Side-by-side V2 strategy. Build `CountdownV2` and `OTPTimerV2` next to the originals, port generator code in place, then cut over and re-enable strict concurrency. `Countdown` becomes a `final class Sendable` with `OSAllocatedUnfairLock<State>` storage and a lazy producer task; `OTPTimer` becomes a `@MainActor @Observable final class` consuming `Countdown.ticks: AsyncStream<Tick>`.

**Tech Stack:** Swift 6.2, `@Observable` (Observation framework), `swift-clocks` 1.0.6, `os.OSAllocatedUnfairLock`, swift-testing.

**Spec:** `docs/superpowers/specs/2026-05-20-swift6-migration-design.md`.
**Conventions:** `CLAUDE.md` (commit style, test naming, what-not-to-do).
**Branch:** `chore/swift-6-migration` (current). `Package.swift` already declares iOS 17 / macOS 14, swift-clocks 1.0.6, and the approachable-concurrency upcoming-feature set — no preparatory phase needed.

---

## File structure

Post-cutover (Phase 5), the final shape:

```
Sources/SwiftyOTP/
├── Generators/
│   ├── HOTPGenerator.swift          (modified: + Sendable)
│   ├── TOTPGenerator.swift          (modified: + Sendable, @Sendable closure)
│   ├── Seed.swift                   (modified: + Sendable)
│   ├── HashingAlgorithm.swift       (modified: + Sendable)
│   └── OTPDigitsChecker.swift       (unchanged)
├── Helpers/
│   ├── Data+Utils.swift             (unchanged)
│   ├── Numbers+Utils.swift          (unchanged)
│   └── UInt64+Data.swift            (unchanged)
└── Timer/
    ├── Countdown.swift              (rewritten via V2 → rename)
    ├── OTPTimer.swift               (rewritten via V2 → rename)
    ├── OTPTimer+TOTPGenerator.swift (rewritten via V2 → rename)
    └── TOTPProvider.swift           (modified: + Sendable)

Tests/SwiftyOTPTests/
├── Helper/
│   ├── LeakTrackingTestCase.swift   (new)
│   ├── AsyncStreamCollect.swift     (new)
│   ├── TaskMegaYield.swift          (new)
│   └── DateBox.swift                (new)
├── CountdownTests.swift             (rewritten in swift-testing via V2 → rename)
├── OTPTimerTests.swift              (rewritten in swift-testing via V2 → rename)
├── OTPTimerIntegrationTests.swift   (rewritten in swift-testing via V2 → rename)
├── HOTPGeneratorTests.swift         (rewritten in swift-testing in place)
├── TOTPGeneratorTests.swift         (rewritten in swift-testing in place)
└── SeedTests.swift                  (rewritten in swift-testing in place)
```

During the migration, V2 files coexist with the originals. They are renamed at cutover (Phase 5).

**Files deleted at cutover (Phase 5):**
- `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
- `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
- `Tests/SwiftyOTPTests/Helper/DateProvider.swift`

**Build/test commands:** The CLAUDE.md convention is to use the MCP tools `BuildProject`, `RunAllTests`, `RunSomeTests` rather than shell. Shell fallbacks: `swift build` and `swift test --filter <TestSuiteName>`.

---

# Phase 1 — Test helpers

Add the swift-testing infrastructure used by every subsequent phase. Nothing touches `Sources/` or breaks the existing XCTest suite.

### Task 1.1: `LeakTrackingTestCase`

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/LeakTrackingTestCase.swift`

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  LeakTrackingTestCase.swift
//  SwiftyOTPTests
//
//  Base class for swift-testing suites that need memory-leak assertions.
//  Subclass and call `trackForMemoryLeaks(_:)` on reference types you want
//  to assert get deallocated by end of test. Swift Testing creates a fresh
//  instance per `@Test`, so `deinit` runs per-test.
//
//  SINGLE-THREADED BY CONTRACT: do not call `addTeardownBlock` from
//  background tasks. Tests that spawn child tasks should ensure those
//  tasks have finished before the test function returns.
//

import Testing

class LeakTrackingTestCase {
    private var teardownBlocks: [() -> Void] = []

    deinit {
        for block in teardownBlocks { block() }
    }

    func addTeardownBlock(_ block: @escaping () -> Void) {
        teardownBlocks.append(block)
    }

    func trackForMemoryLeaks(
        _ instance: AnyObject,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        addTeardownBlock { [weak instance] in
            #expect(
                instance == nil,
                "Instance should have been deallocated. Potential memory leak.",
                sourceLocation: sourceLocation
            )
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles.**

Use `BuildProject` (MCP) or shell fallback: `swift build`.
Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/LeakTrackingTestCase.swift
git commit -m "add \`LeakTrackingTestCase\` base class for swift-testing memory-leak checks"
```

### Task 1.2: `AsyncSequence.collect(_:)` helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/AsyncStreamCollect.swift`

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  AsyncStreamCollect.swift
//  SwiftyOTPTests
//
//  Pull the first N values from an AsyncSequence into an array.
//  Pairs with `swift-clocks` `TestClock.advance(by:)` for deterministic tests.
//

import Foundation

extension AsyncSequence where Element: Sendable {
    /// Collect the first `count` elements of this stream into an array.
    /// If the sequence ends before `count` elements arrive, returns what was collected.
    func collect(_ count: Int) async rethrows -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        var iterator = makeAsyncIterator()
        for _ in 0..<count {
            guard let next = try await iterator.next() else { break }
            result.append(next)
        }
        return result
    }
}
```

- [ ] **Step 2: Build to verify.**

`BuildProject` (or `swift build`). Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/AsyncStreamCollect.swift
git commit -m "add \`collect(_:)\` helper to pull a fixed prefix from an \`AsyncSequence\`"
```

### Task 1.3: `Task.megaYield` helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/TaskMegaYield.swift`

`TestClock.advance(by:)` only fires `clock.timer` / `clock.sleep` continuations that are already suspended on the clock. When a producer task is spawned synchronously from a subscribe call, it may not yet have reached its first suspension by the time the test calls `advance`. `megaYield` repeatedly hops the cooperative pool to give those tasks scheduling opportunities. swift-clocks' own test suite uses an equivalent helper.

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  TaskMegaYield.swift
//  SwiftyOTPTests
//
//  Cooperative-scheduling helper so producer tasks reach their first
//  `clock.timer`/`clock.sleep` suspension before the test advances time.
//  Mirrors swift-clocks' internal test helper.
//

extension Task where Success == Never, Failure == Never {
    static func megaYield(count: Int = 20) async {
        for _ in 0..<count {
            await Task<Void, Never>.detached(priority: .background) {
                await Task.yield()
            }.value
        }
    }
}
```

- [ ] **Step 2: Build to verify.**

`BuildProject` (or `swift build`). Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/TaskMegaYield.swift
git commit -m "add \`Task.megaYield\` to drain cooperative scheduling in clock tests"
```

### Task 1.4: `DateBox` helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/DateBox.swift`

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  DateBox.swift
//  SwiftyOTPTests
//
//  Sendable date provider that mints monotonically-increasing one-second
//  steps. Matches the cadence of `clock.timer(interval: .seconds(1))` so
//  tick.date is deterministic when paired with `TestClock`.
//
//  TEST-ONLY. Do NOT copy into Sources/ — CLAUDE.md forbids
//  `@unchecked Sendable` in production code.
//

import Foundation
import os

final class DateBox: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Date>

    init(start: Date) {
        self.lock = OSAllocatedUnfairLock(initialState: start)
    }

    func next() -> Date {
        lock.withLock { current in
            let value = current
            current.addTimeInterval(1)
            return value
        }
    }
}
```

- [ ] **Step 2: Build to verify.**

`BuildProject` (or `swift build`). Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/DateBox.swift
git commit -m "add \`DateBox\` sendable date provider for deterministic clock tests"
```

---

# Phase 2 — `CountdownV2`

Build the new `Countdown` next to the old one. Use strict TDD: write a failing test, implement the minimal code to pass, run, commit. Tests grow incrementally; the implementation evolves to support them.

### Task 2.1: `Tick` value type + `CountdownV2` skeleton

**Files:**
- Create: `Sources/SwiftyOTP/Timer/CountdownV2.swift`

We start with the public surface and a `ticks` stub that returns an empty stream. No producer logic yet — TDD will drive that in.

- [ ] **Step 1: Create the file with the skeleton.**

```swift
//
//  CountdownV2.swift
//  SwiftyOTP
//
//  V2 of `Countdown` — swift-clocks-driven, broadcasts ticks via AsyncStream.
//  Renamed to `Countdown` at cutover (Phase 5).
//

import Foundation
import os
import Clocks

public struct Tick: Sendable, Equatable {
    public let value: TimeInterval
    public let date: Date
    public let windowChanged: Bool

    public init(value: TimeInterval, date: Date, windowChanged: Bool) {
        self.value = value
        self.date = date
        self.windowChanged = windowChanged
    }
}

public final class CountdownV2: Sendable {
    public let timeStep: UInt

    fileprivate struct State {
        var subscribers: [UUID: AsyncStream<Tick>.Continuation] = [:]
        var producerTask: Task<Void, Never>?
        var lastWindow: UInt?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let clock: any Clock<Duration>
    private let dateProvider: @Sendable () -> Date

    public init(
        timeStep: UInt,
        clock: any Clock<Duration> = ContinuousClock(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.timeStep = timeStep
        self.clock = clock
        self.dateProvider = dateProvider
    }

    public var ticks: AsyncStream<Tick> {
        AsyncStream { _ in }   // Implemented in Task 2.2.
    }
}
```

- [ ] **Step 2: Build to verify the skeleton compiles.**

`BuildProject` (or `swift build`). Expected: clean build. Warnings about unused `clock` and `dateProvider` are acceptable for now.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/CountdownV2.swift
git commit -m "add \`CountdownV2\` skeleton with \`Tick\` value type and locked state"
```

### Task 2.2: First behavior — emits cadenced ticks

**Files:**
- Create: `Tests/SwiftyOTPTests/CountdownV2Tests.swift`
- Modify: `Sources/SwiftyOTP/Timer/CountdownV2.swift` (implement `ticks` + producer)

- [ ] **Step 1: Write the failing test.**

```swift
//
//  CountdownV2Tests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import Clocks
@testable import SwiftyOTP

@Suite("CountdownV2")
final class CountdownV2Tests: LeakTrackingTestCase {

    @Test
    func `ticks - emits aligned countdown values at one-second cadence`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        let collected = Task { await sut.ticks.collect(3) }
        await Task.megaYield()
        await clock.advance(by: .seconds(3))
        let ticks = await collected.value

        #expect(ticks.map(\.value) == [29, 28, 27])
    }
}

private extension CountdownV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: CountdownV2, clock: TestClock<Duration>, date: DateBox) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let sut = CountdownV2(timeStep: timeStep, clock: clock, dateProvider: { dateBox.next() })
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock, dateBox)
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

`RunSomeTests` (MCP) filtered to `CountdownV2Tests`, or shell fallback: `swift test --filter CountdownV2Tests`.
Expected: FAIL. The skeleton returns an empty `AsyncStream { _ in }` so `collect(3)` returns `[]`.

- [ ] **Step 3: Implement `ticks` + the producer.**

Replace the body of `var ticks: AsyncStream<Tick>` in `CountdownV2.swift` and add the supporting private members. The full updated file is:

```swift
//
//  CountdownV2.swift
//  SwiftyOTP
//
//  V2 of `Countdown` — swift-clocks-driven, broadcasts ticks via AsyncStream.
//  Renamed to `Countdown` at cutover (Phase 5).
//

import Foundation
import os
import Clocks

public struct Tick: Sendable, Equatable {
    public let value: TimeInterval
    public let date: Date
    public let windowChanged: Bool

    public init(value: TimeInterval, date: Date, windowChanged: Bool) {
        self.value = value
        self.date = date
        self.windowChanged = windowChanged
    }
}

public final class CountdownV2: Sendable {
    public let timeStep: UInt

    fileprivate struct State {
        var subscribers: [UUID: AsyncStream<Tick>.Continuation] = [:]
        var producerTask: Task<Void, Never>?
        var lastWindow: UInt?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let clock: any Clock<Duration>
    private let dateProvider: @Sendable () -> Date

    public init(
        timeStep: UInt,
        clock: any Clock<Duration> = ContinuousClock(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.timeStep = timeStep
        self.clock = clock
        self.dateProvider = dateProvider
    }

    public var ticks: AsyncStream<Tick> {
        AsyncStream { continuation in
            let id = UUID()
            let needsStart = state.withLock { state -> Bool in
                state.subscribers[id] = continuation
                return state.producerTask == nil
            }
            if needsStart { startProducer() }
            continuation.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        }
    }

    private func unsubscribe(id: UUID) {
        state.withLock { state in
            state.subscribers.removeValue(forKey: id)
            if state.subscribers.isEmpty {
                state.producerTask?.cancel()
                state.producerTask = nil
                state.lastWindow = nil
            }
        }
    }

    private func startProducer() {
        let task = Task { [weak self] in
            guard let self else { return }
            for await _ in self.clock.timer(interval: .seconds(1)) {
                if Task.isCancelled { return }
                self.broadcastTick()
            }
        }
        state.withLock { $0.producerTask = task }
    }

    private func broadcastTick() {
        let now = dateProvider()
        let windowSize = Double(timeStep)
        let timestamp = now.timeIntervalSince1970
        let currentWindow = UInt(timestamp) / timeStep
        let value = windowSize - timestamp.truncatingRemainder(dividingBy: windowSize)

        let (tick, subs) = state.withLock { state -> (Tick, [AsyncStream<Tick>.Continuation]) in
            let windowChanged = state.lastWindow.map { currentWindow > $0 } ?? true
            state.lastWindow = currentWindow
            let tick = Tick(value: value, date: now, windowChanged: windowChanged)
            return (tick, Array(state.subscribers.values))
        }

        for sub in subs { sub.yield(tick) }
    }
}
```

- [ ] **Step 4: Run the test, expect pass.**

`RunSomeTests` (MCP) filtered to `CountdownV2Tests`.
Expected: PASS — `ticks.map(\.value) == [29, 28, 27]`.

If the test hangs or returns fewer than 3 values, increase the yield count: `await Task.megaYield(count: 50)`. A test that needs more than 50 is a smell — investigate before bumping further.

- [ ] **Step 5: Run the full suite to confirm no regression.**

`RunAllTests` (MCP) or `swift test`. Expected: green (existing XCTest + the one new swift-testing case).

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/CountdownV2.swift Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "$(cat <<'EOF'
implement \`CountdownV2.ticks\` cadenced producer with \`AsyncStream\` broadcast

producer task starts on first subscriber and is cancelled when the last
subscriber drops. state lives behind \`OSAllocatedUnfairLock\`. one
swift-testing case asserts one-second cadence via \`TestClock.advance\`
and \`collect(N)\`.
EOF
)"
```

### Task 2.3: `windowChanged` is true on the first emission

**Files:**
- Modify: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` (append a test)

- [ ] **Step 1: Append the test.**

Inside `final class CountdownV2Tests`, after the first `@Test` method, add:

```swift
@Test
func `ticks - reports windowChanged true on the first emission`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    let collected = Task { await sut.ticks.collect(1) }
    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    let ticks = await collected.value

    #expect(ticks.first?.windowChanged == true)
}
```

- [ ] **Step 2: Run the test, expect pass.**

`RunSomeTests` filtered to `CountdownV2Tests`. Expected: PASS. The current `broadcastTick` returns `windowChanged = true` when `lastWindow == nil`, which is the case for the first emission.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "assert \`CountdownV2.ticks\` reports \`windowChanged\` true on the first emission"
```

### Task 2.4: `windowChanged` is true when crossing a window boundary

**Files:**
- Modify: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` (append a test)

- [ ] **Step 1: Append the test.**

Inside `final class CountdownV2Tests`:

```swift
@Test
func `ticks - reports windowChanged true when crossing a window boundary`() async {
    // Start at t=27 so the boundary at t=30 falls inside the collected ticks.
    let (sut, clock, _) = makeSUT(startingAt: 27)

    let collected = Task { await sut.ticks.collect(5) }
    await Task.megaYield()
    await clock.advance(by: .seconds(5))
    let ticks = await collected.value

    // DateBox starts at t=27 and advances by 1s per call.
    // The producer asks for `dateProvider()` once per tick:
    // Tick 1: now=27, currentWindow=0, value=30-27=3,  windowChanged=true  (first emission)
    // Tick 2: now=28, currentWindow=0, value=30-28=2,  windowChanged=false
    // Tick 3: now=29, currentWindow=0, value=30-29=1,  windowChanged=false
    // Tick 4: now=30, currentWindow=1, value=30-0=30,  windowChanged=true  (boundary)
    // Tick 5: now=31, currentWindow=1, value=30-1=29,  windowChanged=false
    #expect(ticks.map(\.windowChanged) == [true, false, false, true, false])
    #expect(ticks.map(\.value) == [3, 2, 1, 30, 29])
}
```

- [ ] **Step 2: Run the test.**

`RunSomeTests` filtered to `CountdownV2Tests`. Expected: PASS.

If it fails, the most likely cause is the `value` calculation at a window boundary. At `now=30`, `timestamp.truncatingRemainder(dividingBy: 30) == 0`, so `value = 30 - 0 = 30`. Confirm `value == 30` for the boundary tick.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "assert \`CountdownV2.ticks\` flips \`windowChanged\` true when crossing a window boundary"
```

### Task 2.5: Multiple subscribers receive the same tick stream

**Files:**
- Modify: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` (append a test)

- [ ] **Step 1: Append the test.**

```swift
@Test
func `ticks - multiple subscribers receive the same tick stream`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    let a = Task { await sut.ticks.collect(2) }
    let b = Task { await sut.ticks.collect(2) }
    await Task.megaYield()
    await clock.advance(by: .seconds(2))

    let aTicks = await a.value
    let bTicks = await b.value

    #expect(aTicks == bTicks)
    #expect(aTicks.count == 2)
}
```

- [ ] **Step 2: Run the test.**

`RunSomeTests` filtered to `CountdownV2Tests`. Expected: PASS. Both subscribers register before `clock.advance`, so both see the same two ticks.

If flaky (one subscriber misses the first tick), bump `Task.megaYield(count: 50)` and re-run.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "assert \`CountdownV2.ticks\` fans out the same tick stream to multiple subscribers"
```

### Task 2.6: Producer resumes after all subscribers drop

**Files:**
- Modify: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` (append a test)

- [ ] **Step 1: Append the test.**

```swift
@Test
func `ticks - resumes correctly after all subscribers drop and a new one subscribes`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    // First subscription: collect 2 ticks, then drop.
    let first = Task { await sut.ticks.collect(2) }
    await Task.megaYield()
    await clock.advance(by: .seconds(2))
    _ = await first.value

    // Allow termination handlers to run and the producer to be torn down.
    await Task.megaYield()

    // Second subscription: collect 2 more ticks.
    let second = Task { await sut.ticks.collect(2) }
    await Task.megaYield()
    await clock.advance(by: .seconds(2))
    let secondTicks = await second.value

    // The second subscription sees windowChanged=true on its first tick because
    // `lastWindow` is reset when the producer is torn down.
    #expect(secondTicks.count == 2)
    #expect(secondTicks.first?.windowChanged == true)
}
```

- [ ] **Step 2: Run the test.**

`RunSomeTests` filtered to `CountdownV2Tests`. Expected: PASS.

The test verifies the lifecycle invariant: when `subscribers.isEmpty`, the producer is cancelled AND `lastWindow` is reset, so a fresh subscription gets `windowChanged == true` on its first tick.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "assert \`CountdownV2\` producer tears down on last unsubscribe and resumes for a fresh subscriber"
```

---

# Phase 3 — `OTPTimerV2`

Build `@MainActor @Observable final class OTPTimerV2` next to the existing `OTPTimer`.

### Task 3.1: `TOTPProvider` becomes `Sendable`

**Files:**
- Modify: `Sources/SwiftyOTP/Timer/TOTPProvider.swift`

- [ ] **Step 1: Add `Sendable` to the protocol.**

Find the line `public protocol TOTPProvider {` and change it to `public protocol TOTPProvider: Sendable {`. The full file (preserving the existing doc comment) becomes:

```swift
//
//  TOTPProvider.swift
//
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation

public protocol TOTPProvider: Sendable {
    typealias OTP = String

    func otp(intervalSince1970: TimeInterval) -> OTP
}
```

(The original doc comment can stay; the meaningful change is the `: Sendable` conformance.)

- [ ] **Step 2: Build to verify.**

`BuildProject`. Expected: clean build. The old `OTPTimer` already uses `TOTPProvider` as a stored property; existing conformers like `TOTPGenerator` will satisfy `Sendable` only after Phase 4. The relaxed concurrency mode keeps this from being a hard error in the meantime.

If the build fails because `TOTPGenerator` is required to be `Sendable` immediately, downgrade the change: leave the protocol as-is and revisit in Phase 4. Otherwise proceed.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/TOTPProvider.swift
git commit -m "mark \`TOTPProvider\` protocol \`Sendable\`"
```

### Task 3.2: `OTPTimerV2` skeleton

**Files:**
- Create: `Sources/SwiftyOTP/Timer/OTPTimerV2.swift`

- [ ] **Step 1: Create the file with the skeleton.**

```swift
//
//  OTPTimerV2.swift
//  SwiftyOTP
//
//  V2 of `OTPTimer` — `@MainActor @Observable`, consumes `CountdownV2.ticks`.
//  Renamed to `OTPTimer` at cutover (Phase 5).
//

import Foundation
import Observation

@MainActor
@Observable
public final class OTPTimerV2 {
    public let timeStep: UInt
    public private(set) var currentOTP: String = ""
    public private(set) var countdown: TimeInterval = 0

    @ObservationIgnored private let countdownSource: CountdownV2
    @ObservationIgnored private let totpProvider: any TOTPProvider
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var lastOTP: String?

    public init(
        countdown: CountdownV2,
        totpProvider: any TOTPProvider,
        startsAutomatically: Bool = true
    ) {
        self.countdownSource = countdown
        self.totpProvider = totpProvider
        self.timeStep = countdown.timeStep
        if startsAutomatically { start() }
    }

    public func start() {
        // Implemented in Task 3.4.
    }

    public func stop() {
        // Implemented in Task 3.4.
    }

    deinit {
        // Cancellation is nonisolated; safe from @MainActor deinit.
        consumerTask?.cancel()
    }
}
```

- [ ] **Step 2: Build.**

`BuildProject`. Expected: clean build (warnings about unused `consumerTask` / `lastOTP` are acceptable).

If the build fails with "cannot find 'TOTPProvider' in scope" or similar, ensure `import Foundation` is present and that Task 3.1 (Sendable on TOTPProvider) was completed.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2.swift
git commit -m "add \`OTPTimerV2\` skeleton as \`@MainActor @Observable\` class"
```

### Task 3.3: First `OTPTimerV2` tests — initial state

**Files:**
- Create: `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift`

- [ ] **Step 1: Create the test file with initial-state assertions.**

```swift
//
//  OTPTimerV2Tests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import Clocks
import os
@testable import SwiftyOTP

@MainActor
@Suite("OTPTimerV2")
final class OTPTimerV2Tests: LeakTrackingTestCase {

    @Test
    func `currentOTP - is empty before any tick is consumed`() async {
        let (sut, _, _) = makeSUT(startsAutomatically: false)

        #expect(sut.currentOTP == "")
        #expect(sut.countdown == 0)
    }

    @Test
    func `init - exposes timeStep from the countdown source`() async {
        let (sut, _, _) = makeSUT(timeStep: 60, startsAutomatically: false)

        #expect(sut.timeStep == 60)
    }
}

@MainActor
private extension OTPTimerV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        startsAutomatically: Bool = true,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: OTPTimerV2, clock: TestClock<Duration>, spy: OTPProviderSpy) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let countdown = CountdownV2(
            timeStep: timeStep,
            clock: clock,
            dateProvider: { dateBox.next() }
        )
        let spy = OTPProviderSpy()
        let sut = OTPTimerV2(
            countdown: countdown,
            totpProvider: spy,
            startsAutomatically: startsAutomatically
        )
        trackForMemoryLeaks(countdown, sourceLocation: sourceLocation)
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock, spy)
    }
}

/// Sendable provider that returns "0", "1", "2", … on successive calls.
/// File-private to this suite.
fileprivate final class OTPProviderSpy: TOTPProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func otp(intervalSince1970: TimeInterval) -> OTP {
        lock.withLock { count in
            defer { count += 1 }
            return "\(count)"
        }
    }
}
```

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `OTPTimerV2Tests`. Expected: PASS — both initial-state tests pass against the skeleton (because `start`/`stop` are no-ops and the consumer task never runs with `startsAutomatically: false`).

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/OTPTimerV2Tests.swift
git commit -m "scaffold \`OTPTimerV2Tests\` with initial-state assertions and \`makeSUT\` factory"
```

### Task 3.4: Implement `start` / `stop` consumer loop + behavior tests

**Files:**
- Modify: `Sources/SwiftyOTP/Timer/OTPTimerV2.swift`
- Modify: `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` (append behavior tests)

- [ ] **Step 1: Append the failing tests.**

Inside `final class OTPTimerV2Tests`, after the two existing `@Test` methods, add:

```swift
@Test
func `start - updates currentOTP from provider on first tick`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    await Task.megaYield()

    #expect(sut.currentOTP == "0")
}

@Test
func `currentOTP - changes only when the window boundary is crossed`() async {
    let (sut, clock, _) = makeSUT(startingAt: 27)

    await Task.megaYield()
    // Tick 1 (now=27, windowChanged=true) → otp "0"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let firstOTP = sut.currentOTP

    // Tick 2 (now=28, windowChanged=false) → reuse "0"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let sameWindowOTP = sut.currentOTP

    // Tick 3 (now=29, windowChanged=false) → reuse "0"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let stillSameOTP = sut.currentOTP

    // Tick 4 (now=30, windowChanged=true) → otp "1"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let nextWindowOTP = sut.currentOTP

    #expect(firstOTP == "0")
    #expect(sameWindowOTP == "0")
    #expect(stillSameOTP == "0")
    #expect(nextWindowOTP == "1")
}

@Test
func `countdown - mirrors the latest tick value`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    await Task.megaYield()
    await clock.advance(by: .seconds(3))
    await Task.megaYield()

    // Last tick at now=2 → countdown = 30 - 2 = 28
    // (DateBox emits 0, 1, 2 on three successive calls.)
    #expect(sut.countdown == 28)
}

@Test
func `start - is idempotent when called twice`() async {
    let (sut, clock, _) = makeSUT(startsAutomatically: false)

    sut.start()
    sut.start()

    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    await Task.megaYield()

    // If two consumer tasks were running, the spy would emit "0" then "1" on
    // the same tick. Only one consumer task should be running, so currentOTP == "0".
    #expect(sut.currentOTP == "0")
}

@Test
func `stop - stops updating observable state`() async {
    let (sut, clock, _) = makeSUT(startingAt: 0)

    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let beforeStop = sut.currentOTP

    sut.stop()

    await clock.advance(by: .seconds(60))
    await Task.megaYield()
    let afterStop = sut.currentOTP

    #expect(beforeStop == afterStop)
}
```

- [ ] **Step 2: Run the tests, expect failure.**

`RunSomeTests` filtered to `OTPTimerV2Tests`. Expected: the five new tests FAIL — `currentOTP` stays empty because `start`/`stop` are no-ops.

- [ ] **Step 3: Implement `start`, `stop`, and `handle(tick:)`.**

Replace the empty bodies of `start()` and `stop()` in `OTPTimerV2.swift`, and add the private `handle(tick:)` method. Insert above the `deinit` (after `stop()`):

```swift
public func start() {
    guard consumerTask == nil else { return }
    consumerTask = Task { [weak self] in
        guard let stream = self?.countdownSource.ticks else { return }
        for await tick in stream {
            guard let self else { return }
            self.handle(tick: tick)
        }
    }
}

public func stop() {
    consumerTask?.cancel()
    consumerTask = nil
}

private func handle(tick: Tick) {
    let otp: String
    if tick.windowChanged || lastOTP == nil {
        otp = totpProvider.otp(intervalSince1970: tick.date.timeIntervalSince1970)
    } else {
        otp = lastOTP ?? ""
    }
    lastOTP = otp
    currentOTP = otp
    countdown = tick.value
}
```

After applying, the full `OTPTimerV2.swift` is:

```swift
//
//  OTPTimerV2.swift
//  SwiftyOTP
//
//  V2 of `OTPTimer` — `@MainActor @Observable`, consumes `CountdownV2.ticks`.
//  Renamed to `OTPTimer` at cutover (Phase 5).
//

import Foundation
import Observation

@MainActor
@Observable
public final class OTPTimerV2 {
    public let timeStep: UInt
    public private(set) var currentOTP: String = ""
    public private(set) var countdown: TimeInterval = 0

    @ObservationIgnored private let countdownSource: CountdownV2
    @ObservationIgnored private let totpProvider: any TOTPProvider
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var lastOTP: String?

    public init(
        countdown: CountdownV2,
        totpProvider: any TOTPProvider,
        startsAutomatically: Bool = true
    ) {
        self.countdownSource = countdown
        self.totpProvider = totpProvider
        self.timeStep = countdown.timeStep
        if startsAutomatically { start() }
    }

    public func start() {
        guard consumerTask == nil else { return }
        consumerTask = Task { [weak self] in
            guard let stream = self?.countdownSource.ticks else { return }
            for await tick in stream {
                guard let self else { return }
                self.handle(tick: tick)
            }
        }
    }

    public func stop() {
        consumerTask?.cancel()
        consumerTask = nil
    }

    private func handle(tick: Tick) {
        let otp: String
        if tick.windowChanged || lastOTP == nil {
            otp = totpProvider.otp(intervalSince1970: tick.date.timeIntervalSince1970)
        } else {
            otp = lastOTP ?? ""
        }
        lastOTP = otp
        currentOTP = otp
        countdown = tick.value
    }

    deinit {
        consumerTask?.cancel()
    }
}
```

The `Task { [weak self] in ... }` closure inherits `@MainActor` isolation from the enclosing class because `start()` is `@MainActor` (the class is). If the compiler complains that the closure is non-isolated, mark it explicitly: `Task { @MainActor [weak self] in ... }`.

- [ ] **Step 4: Run the tests, expect pass.**

`RunSomeTests` filtered to `OTPTimerV2Tests`. Expected: all seven tests PASS.

If `start - is idempotent` fails with `currentOTP == "1"` instead of `"0"`, two consumer tasks are running. Verify the `guard consumerTask == nil` early return is in place.

- [ ] **Step 5: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2.swift Tests/SwiftyOTPTests/OTPTimerV2Tests.swift
git commit -m "$(cat <<'EOF'
implement \`OTPTimerV2.start\`/\`stop\` consumer loop with window-aware OTP cache

a single consumer task subscribes to \`CountdownV2.ticks\` and updates
\`currentOTP\` and \`countdown\` on \`MainActor\`. otp recomputation
only happens on window changes; \`start\` is idempotent; \`stop\`
cancels the consumer task.
EOF
)"
```

### Task 3.5: Convenience initialisers

**Files:**
- Create: `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift`

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  OTPTimerV2+TOTPGenerator.swift
//  SwiftyOTP
//
//  Convenience initialisers that wrap a `TOTPGenerator` (or a `Seed`) and
//  construct a `CountdownV2` for the consumer. Renamed at cutover (Phase 5).
//

import Foundation

public extension OTPTimerV2 {
    /// Convenience initialiser using an existing `TOTPGenerator`.
    convenience init(
        totpGenerator: TOTPGenerator,
        timeStep: UInt = 30,
        startsAutomatically: Bool = true
    ) {
        self.init(
            countdown: CountdownV2(timeStep: timeStep),
            totpProvider: totpGenerator,
            startsAutomatically: startsAutomatically
        )
    }

    /// Convenience initialiser building a `TOTPGenerator` from a `Seed`.
    convenience init(
        seed: Seed,
        digits: Int = 6,
        timeStep: UInt = 30,
        algorithm: HashingAlgorithm = .sha1,
        startsAutomatically: Bool = true
    ) throws {
        let provider = try TOTPGenerator(
            seed: seed,
            digits: digits,
            timeStep: timeStep,
            algorithm: algorithm
        )
        self.init(
            countdown: CountdownV2(timeStep: timeStep),
            totpProvider: provider,
            startsAutomatically: startsAutomatically
        )
    }
}
```

- [ ] **Step 2: Build to verify.**

`BuildProject`. Expected: clean build.

`TOTPGenerator: TOTPProvider` conformance lives in the soon-to-be-deleted `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift`. That file stays until cutover, so the conformance is in scope here. No action needed.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift
git commit -m "add \`OTPTimerV2\` convenience initialisers for \`TOTPGenerator\` and \`Seed\`"
```

### Task 3.6: Integration test against RFC 6238 vectors

**Files:**
- Create: `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift`

- [ ] **Step 1: Create the test file.**

```swift
//
//  OTPTimerV2IntegrationTests.swift
//  SwiftyOTPTests
//
//  Exercises `OTPTimerV2` with a real `TOTPGenerator` and asserts that
//  emitted OTPs match RFC 6238 reference vectors across a window boundary.
//

import Testing
import Foundation
import Clocks
@testable import SwiftyOTP

@MainActor
@Suite("OTPTimerV2 integration")
final class OTPTimerV2IntegrationTests: LeakTrackingTestCase {

    /// RFC 6238 SHA-1 test seed.
    private var seedSha1: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `currentOTP - matches RFC 6238 SHA-1 vectors across a window boundary`() async throws {
        // RFC 6238 vectors (8-digit, SHA-1):
        //   t=59  → 94287082
        //   t=29  → 84755224 (counter floor 29/30 = 0)
        //
        // Start at t=28 so the first three ticks straddle the t=30 boundary.
        let (sut, clock) = try makeSUT(startingAt: 28)

        await Task.megaYield()

        // Tick 1: now=28, windowChanged=true,  otp = otp(at: 28) = 84755224
        // Tick 2: now=29, windowChanged=false, otp = "84755224" (cached)
        // Tick 3: now=30, windowChanged=true,  otp = otp(at: 30) = 94287082
        await clock.advance(by: .seconds(3))
        await Task.megaYield()

        #expect(sut.currentOTP == "94287082")
    }
}

@MainActor
private extension OTPTimerV2IntegrationTests {
    func makeSUT(
        startingAt secondsSinceEpoch: TimeInterval,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (sut: OTPTimerV2, clock: TestClock<Duration>) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let countdown = CountdownV2(
            timeStep: 30,
            clock: clock,
            dateProvider: { dateBox.next() }
        )
        let provider = try TOTPGenerator(seed: .data(seedSha1), digits: 8, timeStep: 30)
        let sut = OTPTimerV2(
            countdown: countdown,
            totpProvider: provider,
            startsAutomatically: true
        )
        trackForMemoryLeaks(countdown, sourceLocation: sourceLocation)
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock)
    }
}
```

- [ ] **Step 2: Run the test.**

`RunSomeTests` filtered to `OTPTimerV2IntegrationTests`. Expected: PASS.

If the assertion fails with `"84755224"` instead of `"94287082"`, the boundary tick (now=30) is not advancing `lastOTP`. Verify the `windowChanged` calculation in `CountdownV2.broadcastTick` and the window-aware branch in `OTPTimerV2.handle(tick:)`.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift
git commit -m "verify \`OTPTimerV2\` against RFC 6238 SHA-1 vector across a window boundary"
```

---

# Phase 4 — Generators: `Sendable` + test migration

Generators are stateless value types so `Sendable` is just a declaration. Tests migrate in place (no V2 variant) because there's no behavioral change to swap between.

### Task 4.1: `Sendable` on `HashingAlgorithm`

**Files:**
- Modify: `Sources/SwiftyOTP/Generators/HashingAlgorithm.swift`

- [ ] **Step 1: Add `Sendable`.**

Replace the contents of the file with:

```swift
//
//  HashingAlgorithm.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

public enum HashingAlgorithm: Sendable {
    case sha1
    case sha256
    case sha512
}
```

- [ ] **Step 2: Build.**

`BuildProject`. Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Generators/HashingAlgorithm.swift
git commit -m "mark \`HashingAlgorithm\` \`Sendable\`"
```

### Task 4.2: `Sendable` on `Seed`

**Files:**
- Modify: `Sources/SwiftyOTP/Generators/Seed.swift`

- [ ] **Step 1: Add `Sendable` to the enum declaration.**

Find the line `public enum Seed {` and change it to `public enum Seed: Sendable {`. No other changes needed.

- [ ] **Step 2: Build.**

`BuildProject`. Expected: clean build. All associated values (`String`, `Data`) are already `Sendable`.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Generators/Seed.swift
git commit -m "mark \`Seed\` \`Sendable\`"
```

### Task 4.3: `Sendable` on `HOTPGenerator`

**Files:**
- Modify: `Sources/SwiftyOTP/Generators/HOTPGenerator.swift`

- [ ] **Step 1: Add `Sendable` to the struct.**

Find the line `public struct HOTPGenerator {` and change it to `public struct HOTPGenerator: Sendable {`. No other changes.

- [ ] **Step 2: Build.**

`BuildProject`. Expected: clean build. All stored properties (`Data`, `Int`, `HashingAlgorithm`) are `Sendable` (the last only after Task 4.1).

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Generators/HOTPGenerator.swift
git commit -m "mark \`HOTPGenerator\` \`Sendable\`"
```

### Task 4.4: `Sendable` on `TOTPGenerator` + `@Sendable` closure

**Files:**
- Modify: `Sources/SwiftyOTP/Generators/TOTPGenerator.swift`

- [ ] **Step 1: Add `Sendable` and update the date-provider closure type.**

Two edits in the file:

1. Change the struct declaration from `public struct TOTPGenerator {` to `public struct TOTPGenerator: Sendable {`.
2. Change `var currentDateProvider: () -> Date = Date.init` to `var currentDateProvider: @Sendable () -> Date = { Date() }`.

The full file becomes:

```swift
//
//  TOTPGenerator.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

/// Represents a Time-Based One-Time Password (HOTP) generator.
public struct TOTPGenerator: Sendable {
    var currentDateProvider: @Sendable () -> Date = { Date() }

    /// The secret seed data used for generating OTPs.
    public var seed: Data { hotp.seed }

    /// The number of digits in the generated OTP.
    public var digits: Int { hotp.digits }

    /// The hashing algorithm used for OTP generation.
    public var algorithm: HashingAlgorithm { hotp.algorithm }

    /// The timestep for computing the OTP - usually 30 or 60 sec
    public let timeStep: UInt

    private let hotp: HOTPGenerator

    public init(seed: Seed, digits: Int = 6, timeStep: UInt = 30, algorithm: HashingAlgorithm = .sha1) throws {
        self.hotp = try HOTPGenerator(seed: seed, digits: digits, algorithm: algorithm)
        self.timeStep = timeStep
    }

    /// The current One-Time Password (OTP) for the current time.
    public var currentOTP: String {
        otp(at: currentDateProvider())
    }

    /// Generate the One-Time Password (OTP) for the provided Date.
    public func otp(at date: Date) -> String {
        let stepCounter = stepCounter(at: date)
        return hotp.otp(at: stepCounter)
    }
}

public extension TOTPGenerator {
    enum UnixTimestamp: Sendable {
        case seconds(UInt64)
        case milliseconds(UInt64)

        var timestampInSeconds: TimeInterval {
            switch self {
            case let .seconds(timestamp): TimeInterval(timestamp)
            case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
            }
        }
    }

    func otp(unixTimestamp timestamp: UnixTimestamp) -> String {
        otp(at: Date(timeIntervalSince1970: timestamp.timestampInSeconds))
    }

    func otp(intervalSince1970: TimeInterval) -> String {
        otp(at: Date(timeIntervalSince1970: intervalSince1970))
    }
}

// MARK: Helpers
private extension TOTPGenerator {
    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}
```

(The `UnixTimestamp` nested enum also gets `: Sendable` since it's a public type carrying `UInt64`. This was missing from earlier reads but is required for strict concurrency.)

- [ ] **Step 2: Build.**

`BuildProject`. Expected: clean build. The existing `TOTPGeneratorTests` (XCTest) assigns to `currentDateProvider` directly; that assignment now requires a `@Sendable` closure value. The test currently uses `let dateProvider = { Date(timeIntervalSince1970: 59) }` — closures literal at the call site infer `@Sendable` when assigned to a `@Sendable` storage, so the XCTest should still compile under relaxed concurrency. If it doesn't, leave a note and migrate the test in Task 4.6 below.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Generators/TOTPGenerator.swift
git commit -m "mark \`TOTPGenerator\` \`Sendable\` and \`currentDateProvider\` \`@Sendable\`"
```

### Task 4.5: Migrate `HOTPGeneratorTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/HOTPGeneratorTests.swift` (replace contents)

- [ ] **Step 1: Replace the file contents.**

```swift
//
//  HOTPGeneratorTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("HOTPGenerator")
final class HOTPGeneratorTests: LeakTrackingTestCase {

    private var seedData: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    private var rfc4226Vectors: [String] {
        ["755224", "287082", "359152", "969429", "338314",
         "254676", "287922", "162583", "399871", "520489"]
    }

    @Test
    func `init - throws when digits is below the valid range`() {
        #expect(throws: (any Error).self) {
            try HOTPGenerator(seed: .data(self.seedData), digits: 5)
        }
    }

    @Test
    func `init - throws when digits is above the valid range`() {
        #expect(throws: (any Error).self) {
            try HOTPGenerator(seed: .data(self.seedData), digits: 9)
        }
    }

    @Test
    func `otp(at:) - generates RFC 4226 reference vectors`() throws {
        let sut = try HOTPGenerator(seed: .data(seedData))

        for (counter, expected) in rfc4226Vectors.enumerated() {
            let actual = sut.otp(at: UInt64(counter))
            #expect(actual == expected, "counter \(counter)")
        }
    }
}
```

Note: `HOTPGenerator.otp(at:)` is `internal` (not `public`). The `@testable import SwiftyOTP` at the top makes it accessible.

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `HOTPGeneratorTests`. Expected: PASS.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/HOTPGeneratorTests.swift
git commit -m "migrate \`HOTPGeneratorTests\` to swift-testing"
```

### Task 4.6: Migrate `TOTPGeneratorTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/TOTPGeneratorTests.swift` (replace contents)

- [ ] **Step 1: Replace the file contents.**

```swift
//
//  TOTPGeneratorTests.swift
//  SwiftyOTPTests
//
//  RFC 6238 reference vectors:
//  https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("TOTPGenerator")
final class TOTPGeneratorTests: LeakTrackingTestCase {

    private var seedSha1: Data {
        "12345678901234567890".data(using: .ascii)!
    }
    private var seedSha256: Data {
        "12345678901234567890123456789012".data(using: .ascii)!
    }
    private var seedSha512: Data {
        "1234567890123456789012345678901234567890123456789012345678901234".data(using: .ascii)!
    }

    private func makeSUT(
        seed: Data,
        timeStep: UInt = 30,
        digits: Int = 8,
        algo: HashingAlgorithm = .sha1
    ) throws -> TOTPGenerator {
        try TOTPGenerator(seed: .data(seed), digits: digits, timeStep: timeStep, algorithm: algo)
    }

    @Test
    func `init - throws when digits is below the valid range`() {
        #expect(throws: (any Error).self) {
            _ = try self.makeSUT(seed: self.seedSha1, digits: 5)
        }
    }

    @Test
    func `init - throws when digits is above the valid range`() {
        #expect(throws: (any Error).self) {
            _ = try self.makeSUT(seed: self.seedSha1, digits: 9)
        }
    }

    @Test
    func `currentOTP - matches RFC 6238 vectors at t=59 across all hashing algorithms`() throws {
        let dateProvider: @Sendable () -> Date = { Date(timeIntervalSince1970: 59) }

        var sutSha1 = try makeSUT(seed: seedSha1, algo: .sha1)
        var sutSha256 = try makeSUT(seed: seedSha256, algo: .sha256)
        var sutSha512 = try makeSUT(seed: seedSha512, algo: .sha512)

        sutSha1.currentDateProvider = dateProvider
        sutSha256.currentDateProvider = dateProvider
        sutSha512.currentDateProvider = dateProvider

        #expect(sutSha1.currentOTP == "94287082")
        #expect(sutSha256.currentOTP == "46119246")
        #expect(sutSha512.currentOTP == "90693936")
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-1 vectors",
        arguments: [
            (UInt64(59),          "94287082"),
            (UInt64(1111111109),  "07081804"),
            (UInt64(1111111111),  "14050471"),
            (UInt64(1234567890),  "89005924"),
            (UInt64(2000000000),  "69279037"),
            (UInt64(20000000000), "65353130"),
        ] as [(UInt64, String)]
    )
    func sha1Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha1, algo: .sha1)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-256 vectors",
        arguments: [
            (UInt64(59),          "46119246"),
            (UInt64(1111111109),  "68084774"),
            (UInt64(1111111111),  "67062674"),
            (UInt64(1234567890),  "91819424"),
            (UInt64(2000000000),  "90698825"),
            (UInt64(20000000000), "77737706"),
        ] as [(UInt64, String)]
    )
    func sha256Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha256, algo: .sha256)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-512 vectors",
        arguments: [
            (UInt64(59),          "90693936"),
            (UInt64(1111111109),  "25091201"),
            (UInt64(1111111111),  "99943326"),
            (UInt64(1234567890),  "93441116"),
            (UInt64(2000000000),  "38618901"),
            (UInt64(20000000000), "47863826"),
        ] as [(UInt64, String)]
    )
    func sha512Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha512, algo: .sha512)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }
}
```

Notes:
- Parameterized `@Test` requires `arguments` whose element types conform to `Sendable`. `(UInt64, String)` qualifies.
- The function name (e.g. `sha1Vector`) is the swift identifier; the `@Test("…")` display string is the label shown in the test navigator. Backticked function-name + dash convention applies to plain `@Test`; for parameterized tests the display string carries that convention.

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `TOTPGeneratorTests`. Expected: PASS for all cases (2 throwing + 1 cross-algorithm + 6×3 parameterized = 21 invocations).

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/TOTPGeneratorTests.swift
git commit -m "migrate \`TOTPGeneratorTests\` to swift-testing with parameterised RFC 6238 vectors"
```

### Task 4.7: Migrate `SeedTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/SeedTests.swift` (replace contents)

- [ ] **Step 1: Replace the file contents.**

```swift
//
//  SeedTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("Seed")
final class SeedTests: LeakTrackingTestCase {

    private var dataSeed: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `data() - hex matches data() when given the equivalent hex representation`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.hex("3132333435363738393031323334353637383930")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when hex is invalid`() {
        let wrongHex = "3132333435363738393031323334353637383930" + "Z"
        let sut = Seed.hex(wrongHex)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base32 matches data() when given the equivalent base32 representation`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when base32 is invalid`() {
        let wrongBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" + "1"
        let sut = Seed.base32(wrongBase32)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base64 matches data() when given the equivalent base64 representation`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.base64("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when base64 is invalid`() {
        let wrongBase64 = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=" + "!"
        let sut = Seed.base64(wrongBase64)
        #expect(throws: (any Error).self) { try sut.data() }
    }
}
```

Note: `Seed.data()` is `internal` (not `public`); `@testable import SwiftyOTP` makes it accessible.

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `SeedTests`. Expected: PASS.

- [ ] **Step 3: Run the full suite.**

`RunAllTests`. Expected: green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/SeedTests.swift
git commit -m "migrate \`SeedTests\` to swift-testing"
```

---

# Phase 5 — Cutover

Single commit: delete the old types and old XCTest helpers, rename V2 → final names, re-enable `StrictConcurrency`.

### Task 5.1: Cutover

**Files (delete):**
- `Sources/SwiftyOTP/Timer/Countdown.swift` (old, Combine-based)
- `Sources/SwiftyOTP/Timer/OTPTimer.swift` (old, Combine-based)
- `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift` (old)
- `Tests/SwiftyOTPTests/CountdownTests.swift` (old XCTest)
- `Tests/SwiftyOTPTests/OTPTimerTests.swift` (old XCTest)
- `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift` (old XCTest)
- `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
- `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
- `Tests/SwiftyOTPTests/Helper/DateProvider.swift`

**Files (rename + edit):**
- `Sources/SwiftyOTP/Timer/CountdownV2.swift` → `Sources/SwiftyOTP/Timer/Countdown.swift`; `CountdownV2` → `Countdown`
- `Sources/SwiftyOTP/Timer/OTPTimerV2.swift` → `Sources/SwiftyOTP/Timer/OTPTimer.swift`; `OTPTimerV2` → `OTPTimer`
- `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift` → `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift`; `OTPTimerV2` → `OTPTimer`
- `Tests/SwiftyOTPTests/CountdownV2Tests.swift` → `Tests/SwiftyOTPTests/CountdownTests.swift`; `CountdownV2Tests` → `CountdownTests`, `CountdownV2` references in body → `Countdown`
- `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` → `Tests/SwiftyOTPTests/OTPTimerTests.swift`; `OTPTimerV2Tests` → `OTPTimerTests`, `OTPTimerV2` → `OTPTimer`, `CountdownV2` → `Countdown`
- `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift` → `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift`; `OTPTimerV2IntegrationTests` → `OTPTimerIntegrationTests`, type references updated likewise
- `Package.swift` — replace approachable concurrency with `StrictConcurrency`

Don't add `extension TOTPGenerator: TOTPProvider {}` (was in the old `OTPTimer+TOTPGenerator.swift`) — that conformance must be added to the new `OTPTimer+TOTPGenerator.swift` (renamed from `OTPTimerV2+TOTPGenerator.swift`) since it was relying on the soon-to-be-deleted file. See Step 4 below.

- [ ] **Step 1: Delete the old source files and old XCTest helpers.**

```bash
git rm \
  Sources/SwiftyOTP/Timer/Countdown.swift \
  Sources/SwiftyOTP/Timer/OTPTimer.swift \
  Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift \
  Tests/SwiftyOTPTests/CountdownTests.swift \
  Tests/SwiftyOTPTests/OTPTimerTests.swift \
  Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift \
  Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift \
  Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift \
  Tests/SwiftyOTPTests/Helper/DateProvider.swift
```

- [ ] **Step 2: Rename the V2 source files (preserving git history).**

```bash
git mv Sources/SwiftyOTP/Timer/CountdownV2.swift \
       Sources/SwiftyOTP/Timer/Countdown.swift

git mv Sources/SwiftyOTP/Timer/OTPTimerV2.swift \
       Sources/SwiftyOTP/Timer/OTPTimer.swift

git mv Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift \
       Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift

git mv Tests/SwiftyOTPTests/CountdownV2Tests.swift \
       Tests/SwiftyOTPTests/CountdownTests.swift

git mv Tests/SwiftyOTPTests/OTPTimerV2Tests.swift \
       Tests/SwiftyOTPTests/OTPTimerTests.swift

git mv Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift \
       Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift
```

- [ ] **Step 3: Rename all `V2` identifiers inside the moved files.**

Use sed (or your editor's project-wide rename). The exact replacements:

```bash
# CountdownV2 → Countdown
sed -i '' 's/CountdownV2/Countdown/g' \
  Sources/SwiftyOTP/Timer/Countdown.swift \
  Sources/SwiftyOTP/Timer/OTPTimer.swift \
  Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift \
  Tests/SwiftyOTPTests/CountdownTests.swift \
  Tests/SwiftyOTPTests/OTPTimerTests.swift \
  Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift

# OTPTimerV2 → OTPTimer
sed -i '' 's/OTPTimerV2/OTPTimer/g' \
  Sources/SwiftyOTP/Timer/OTPTimer.swift \
  Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift \
  Tests/SwiftyOTPTests/OTPTimerTests.swift \
  Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift
```

Also update the suite display strings inside `@Suite(...)` calls so test-navigator labels don't say "V2":
- `Tests/SwiftyOTPTests/CountdownTests.swift`: ensure `@Suite("Countdown")` (already correct since sed leaves it alone).
- `Tests/SwiftyOTPTests/OTPTimerTests.swift`: should now read `@Suite("OTPTimer")` after the sed pass.
- `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift`: should now read `@Suite("OTPTimer integration")` after the sed pass.

The header comments inside the files (e.g. "// V2 of `Countdown` — ... Renamed to `Countdown` at cutover") should be updated. Open each renamed file and replace the leading doc-comment paragraph with a one-line file summary. Example for `Sources/SwiftyOTP/Timer/Countdown.swift`:

```swift
//
//  Countdown.swift
//  SwiftyOTP
//
//  swift-clocks-driven countdown source. Broadcasts `Tick` values via
//  `AsyncStream` to multiple subscribers with shared cadence.
//
```

Apply equivalent edits to `OTPTimer.swift`, `OTPTimer+TOTPGenerator.swift`, and the test files.

- [ ] **Step 4: Add the `TOTPGenerator: TOTPProvider` conformance.**

The old `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift` contained:

```swift
extension TOTPGenerator: TOTPProvider {}
```

This conformance was deleted with the file in Step 1. Add it to the renamed file. Open `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift` (formerly `OTPTimerV2+TOTPGenerator.swift`) and insert before the `public extension OTPTimer { ... }` block:

```swift
extension TOTPGenerator: TOTPProvider {}
```

So the file's top looks like:

```swift
//
//  OTPTimer+TOTPGenerator.swift
//  SwiftyOTP
//
//  Convenience initialisers that wrap a `TOTPGenerator` (or a `Seed`).
//

import Foundation

extension TOTPGenerator: TOTPProvider {}

public extension OTPTimer {
    convenience init(
        totpGenerator: TOTPGenerator,
        timeStep: UInt = 30,
        startsAutomatically: Bool = true
    ) {
        // ...
    }
    // ...
}
```

- [ ] **Step 5: Update `Package.swift` to re-enable strict concurrency.**

Replace the `upcomingFeatures` array with a single `StrictConcurrency` setting. The full file becomes:

```swift
// swift-tools-version: 6.2

import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "SwiftyOTP",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwiftyOTP", targets: ["SwiftyOTP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/norio-nomura/Base32.git", exact: "0.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks.git", exact: "1.0.6")
    ],
    targets: [
        .target(
            name: "SwiftyOTP",
            dependencies: [
                "Base32",
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: upcomingFeatures
        ),
        .testTarget(
            name: "SwiftyOTPTests",
            dependencies: [
                "SwiftyOTP",
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: upcomingFeatures
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 6: Build and verify.**

`BuildProject` (or `swift build`). Expected: clean build. If concurrency diagnostics surface, fix them:
- Closures inside `OTPTimer.start()` may need explicit `@MainActor` annotation: `Task { @MainActor [weak self] in ... }`.
- The `consumerTask` `Task<Void, Never>?` property should not need any extra annotation since the class is `@MainActor`.
- If the compiler complains that `CountdownV2.State`'s `subscribers` dictionary holds `AsyncStream<Tick>.Continuation` (which may not be `Sendable` under strict mode), wrap the access pattern such that no continuation is captured across an `await`. The current implementation already does this — continuations are yielded synchronously inside `broadcastTick`.

Resolve any remaining diagnostics in place. Keep edits minimal.

- [ ] **Step 7: Run the full test suite.**

`RunAllTests` (or `swift test`). Expected: green.

- [ ] **Step 8: Final verification — grep for residue.**

Run these in the project root and verify each returns no output:

```bash
git grep -nE "Combine|Foundation\\.Timer|ObservableObject" -- Sources/
git grep -n "import XCTest" -- Tests/
git grep -nE "V2|CountdownV2|OTPTimerV2" -- Sources/ Tests/
```

If any returns hits, fix them before committing.

- [ ] **Step 9: Stage everything.**

```bash
git add -A
git status
```

Inspect the staged list. Expected:
- 9 deletions (the old source files, XCTest tests, and old helpers from Step 1)
- 6 renames (from Step 2; `git status` may show these as `renamed:` if `git mv` preserved history)
- Several modifications to the renamed files (from Steps 3, 4, and the doc-comment updates)
- One modification: `Package.swift` (Step 5)

If any file is missing or unintended file is staged, run `git status` carefully and adjust.

- [ ] **Step 10: Commit.**

```bash
git commit -m "$(cat <<'EOF'
cut over to swift 6 \`Countdown\` and \`@MainActor @Observable\` \`OTPTimer\`

deletes the combine + \`Foundation.Timer\` + XCTest implementation and
renames the V2 types to their final names. \`Countdown\` is now a
\`final class Sendable\` driven by \`swift-clocks\` with lazy
multi-subscriber fan-out; \`OTPTimer\` is \`@MainActor @Observable\`
with direct observed \`currentOTP\`/\`countdown\` properties.
\`StrictConcurrency\` is re-enabled in \`Package.swift\`.

breaking change: \`OTPTimer.publisher\` and \`OTPTimer.Event\` are gone;
consumers observe \`currentOTP\` and \`countdown\` directly.
\`Countdown.start()\`/\`stop()\` are gone; subscribe to \`ticks\`.
\`interval\` parameter on convenience inits is gone.
EOF
)"
```

- [ ] **Step 11: Post-cutover verification.**

Run `git log --oneline -5` and confirm the cutover commit is present, along with the Phase 1-4 commits. Then run the full suite one more time:

`RunAllTests` (or `swift test`). Expected: green, no `import XCTest`, no `Combine`.

The migration is complete.

---

## Out of scope (documented follow-up)

`code-keeper-authenticator/CodeKeeperApp.swift` and `OTPViewModel.swift` will need updates after this ships:
- `OTPViewModel` → `@Observable` model that owns an `OTPTimer` directly and exposes derived display state (formatted OTP, countdown string, progress).
- `OTPCodeProvider` protocol likely deletable.
- Shared `static let countdown = Countdown(timeStep: 30)` stays.

This work gets its own brainstorming + plan in the consumer repo when this migration ships.
