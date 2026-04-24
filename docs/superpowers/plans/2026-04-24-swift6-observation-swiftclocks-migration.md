# Swift 6 / Observation / swift-clocks Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `SwiftyOTP` from Combine + `Foundation.Timer` + XCTest to a strict-Swift-6, `@MainActor @Observable` `OTPTimer` driven by a `Sendable` `Countdown` over `swift-clocks`, with all tests on swift-testing — without ever leaving the test suite red.

**Architecture:** Side-by-side V2 strategy. We relax concurrency, build `CountdownV2` and `OTPTimerV2` next to the originals, port generator code in place, then cut over and re-enable strict concurrency. `Countdown` is a `final class Sendable` with `OSAllocatedUnfairLock<State>` storage and a lazy producer task; `OTPTimer` is a `@MainActor @Observable final class` consuming `Countdown.ticks: AsyncStream<Tick>`.

**Tech Stack:** Swift 6 (toolchain 6.2), `@Observable` (Observation), `swift-clocks` 1.0.6, `os` (OSAllocatedUnfairLock), swift-testing.

**Spec:** `docs/superpowers/specs/2026-04-24-swift6-observation-swiftclocks-migration-design.md`.
**Conventions:** `CLAUDE.md` (commit style, test naming, what-not-to-do).

---

## File structure

After this plan completes (post-cutover), the final shape is:

```
Sources/SwiftyOTP/
├── Generators/
│   ├── HOTPGenerator.swift          (modified: + Sendable)
│   ├── TOTPGenerator.swift          (modified: + Sendable, @Sendable closures)
│   ├── Seed.swift                   (modified: + Sendable)
│   ├── HashingAlgorithm.swift       (modified: + Sendable)
│   └── OTPDigitsChecker.swift       (unchanged)
├── Helpers/
│   ├── Data+Utils.swift             (unchanged)
│   ├── Numbers+Utils.swift          (unchanged)
│   └── UInt64+Data.swift            (unchanged)
└── Timer/
    ├── Countdown.swift              (rewritten: was Foundation.Timer + Combine; now AsyncStream + swift-clocks)
    ├── OTPTimer.swift               (rewritten: was Combine; now @MainActor @Observable)
    ├── OTPTimer+TOTPGenerator.swift (rewritten: matches new init shape)
    └── TOTPProvider.swift           (unchanged)

Tests/SwiftyOTPTests/
├── Helper/
│   ├── LeakTracker.swift            (new: swift-testing leak helper)
│   ├── AsyncStreamCollect.swift     (new: collect N from AsyncStream)
│   └── TaskMegaYield.swift          (new: scheduling helper for TestClock tests)
├── CountdownTests.swift             (rewritten in swift-testing)
├── OTPTimerTests.swift              (rewritten in swift-testing)
├── OTPTimerIntegrationTests.swift   (rewritten in swift-testing)
├── HOTPGeneratorTests.swift         (rewritten in swift-testing)
├── TOTPGeneratorTests.swift         (rewritten in swift-testing)
└── SeedTests.swift                  (rewritten in swift-testing)
```

During the migration the V2 files coexist with the originals (`CountdownV2.swift`, `OTPTimerV2.swift`, etc.) and are renamed at cutover (Phase 4).

**Files deleted at cutover:**
- `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
- `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
- `Tests/SwiftyOTPTests/Helper/DateProvider.swift`

---

# Phase 0 — Relax concurrency settings & bump platforms

This phase sets up the substrate for everything else: relaxes strict concurrency (so half-migrated states compile), bumps platforms to iOS 17 / macOS 14 (required by `@Observable`).

### Task 0.1: Update `Package.swift`

**Files:**
- Modify: `Package.swift` (replace contents)

- [ ] **Step 1: Read current `Package.swift`** to confirm starting state.

```bash
cat Package.swift
```

Expected: shows `swift-tools-version: 6.2`, `.iOS(.v13), .macOS(.v10_15)`, `.enableUpcomingFeature("StrictConcurrency")`, `swiftLanguageModes: [.v6]`.

- [ ] **Step 2: Replace `Package.swift` with the relaxed-concurrency version.**

```swift
// swift-tools-version: 6.2

import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    // Approachable concurrency — relaxes strict mode so half-migrated states compile.
    // Re-tightened to StrictConcurrency in Phase 4 (cutover).
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
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

- [ ] **Step 3: Build & test from scratch via MCP.**

Use `BuildProject` (or shell fallback `swift build`).
Then `RunAllTests` (or `swift test`).
Expected: clean build, all existing XCTest tests pass.

If build fails because Swift 6 mode is too strict even with relaxed upcoming features, downgrade `swiftLanguageModes: [.v6]` → `swiftLanguageModes: [.v5]` and rerun. Document this temporary downgrade with an inline comment so it isn't forgotten at cutover.

- [ ] **Step 4: Commit.**

```bash
git add Package.swift
git commit -m "$(cat <<'EOF'
relax to approachable concurrency and bump platforms to iOS 17 / macOS 14

prepares the package for the side-by-side migration to `@Observable`
\`OTPTimer\` and `swift-clocks`-driven `Countdown`. strict concurrency
is re-enabled at cutover (phase 4 of the migration plan).
EOF
)"
```

---

# Phase 1 — `CountdownV2` (swift-clocks + AsyncStream + OSAllocatedUnfairLock)

Builds the new `Countdown` next to the old one, plus the swift-testing helpers used by every subsequent test phase.

### Task 1.1: `LeakTracker` helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/LeakTracker.swift`

- [ ] **Step 1: Create `LeakTracker.swift` with full contents.**

```swift
//
//  LeakTracker.swift
//  SwiftyOTPTests
//
//  swift-testing equivalent of the XCTest memory-leak teardown helper.
//

import Testing

/// Final class so `deinit` can fire when the tracker goes out of scope.
/// Hold the returned tracker as a local in your test (or in a tuple from
/// `makeSUT`) to defer the leak check to scope exit.
final class LeakTracker {
    private weak var weakInstance: AnyObject?
    private let sourceLocation: SourceLocation

    init(_ instance: AnyObject, sourceLocation: SourceLocation) {
        self.weakInstance = instance
        self.sourceLocation = sourceLocation
    }

    deinit {
        if weakInstance != nil {
            Issue.record(
                "Instance should have been deallocated. Potential memory leak.",
                sourceLocation: sourceLocation
            )
        }
    }
}

@discardableResult
func trackForMemoryLeaks(
    _ instance: AnyObject,
    sourceLocation: SourceLocation = #_sourceLocation
) -> LeakTracker {
    LeakTracker(instance, sourceLocation: sourceLocation)
}
```

- [ ] **Step 2: Build to verify it compiles.**

`BuildProject` (or `swift build`).
Expected: clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/LeakTracker.swift
git commit -m "add \`LeakTracker\` helper for swift-testing memory-leak checks"
```

### Task 1.2: `AsyncStream` collect helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/AsyncStreamCollect.swift`

- [ ] **Step 1: Create `AsyncStreamCollect.swift` with full contents.**

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

`BuildProject` — expect clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/AsyncStreamCollect.swift
git commit -m "add `collect(_:)` helper to pull a fixed prefix from an `AsyncSequence`"
```

### Task 1.3: `Task.megaYield` helper

**Files:**
- Create: `Tests/SwiftyOTPTests/Helper/TaskMegaYield.swift`

`TestClock.advance(by:)` only fires `clock.timer`/`clock.sleep` continuations that are already suspended on the clock. When a producer task is spawned synchronously from a subscribe call, it may not yet have reached its first suspension by the time the test calls `advance`. `megaYield` repeatedly hops the cooperative pool to give those tasks scheduling opportunities. swift-clocks' own test suite uses an equivalent helper.

- [ ] **Step 1: Create `TaskMegaYield.swift` with full contents.**

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

`BuildProject` — expect clean build.

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/Helper/TaskMegaYield.swift
git commit -m "add \`Task.megaYield\` to drain cooperative scheduling in clock tests"
```

### Task 1.4: `Tick` value type + `CountdownV2` skeleton

**Files:**
- Create: `Sources/SwiftyOTP/Timer/CountdownV2.swift`

We start with the public surface and stored properties only. No producer logic yet — the next tasks add it under TDD.

- [ ] **Step 1: Create `CountdownV2.swift` with the skeleton.**

```swift
//
//  CountdownV2.swift
//  SwiftyOTP
//
//  V2 of `Countdown` — swift-clocks-driven, broadcasts ticks via AsyncStream.
//  Renamed to `Countdown` at cutover (phase 4 of the migration plan).
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

    private struct State {
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
        // Implementation added in Task 1.6.
        AsyncStream { _ in }
    }
}
```

- [ ] **Step 2: Build to verify the skeleton compiles.**

`BuildProject` — expect clean build (warnings about unused `clock`/`dateProvider` are acceptable for now).

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/CountdownV2.swift
git commit -m "add \`CountdownV2\` skeleton with \`Tick\` value type and locked state"
```

### Task 1.5: First `CountdownV2` test — no ticks before subscription

**Files:**
- Create: `Tests/SwiftyOTPTests/CountdownV2Tests.swift`

This task lays down the test file with `makeSUT` + the first behavior assertion: `ticks` doesn't fire anything until someone awaits.

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
struct CountdownV2Tests {

    @Test
    func `ticks - emits no values when no subscriber awaits`() async {
        let (sut, _, clock) = makeSUT()

        // Advance the clock with no subscriber. No producer task should run.
        await clock.advance(by: .seconds(5))

        // If the producer ran, it would still have nowhere to send to,
        // so we instead verify by subscribing AFTER advancing and
        // confirming we don't immediately receive a backlog.
        let stream = sut.ticks
        let receivedAnything = await Task {
            // Race: collect with a timeout via a short clock tick window.
            await Task.megaYield()
            await clock.advance(by: .milliseconds(1))
            return await Task {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }.value
        }.value

        // We only advanced by 1ms after subscribing — no tick should have arrived.
        #expect(receivedAnything == false)
    }
}

private extension CountdownV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: CountdownV2, leak: LeakTracker, clock: TestClock<Duration>) {
        let clock = TestClock()
        let sut = CountdownV2(timeStep: timeStep, clock: clock)
        return (sut, trackForMemoryLeaks(sut, sourceLocation: sourceLocation), clock)
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**

`RunSomeTests` targeting `CountdownV2Tests` (or `swift test --filter CountdownV2Tests`).
Expected: FAIL — `ticks` skeleton returns an empty stream so `receivedAnything` is `false` and the assertion passes accidentally. **This test is fragile by design** — it serves as scaffolding for Task 1.6 where we replace it with a real subscription test. It's OK if it passes against the skeleton; the next task replaces it.

- [ ] **Step 3: Commit (scaffolding only).**

```bash
git add Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "scaffold \`CountdownV2Tests\` with \`makeSUT\` factory"
```

### Task 1.6: Implement subscription + producer loop, write real tests

**Files:**
- Modify: `Sources/SwiftyOTP/Timer/CountdownV2.swift` (replace `ticks` body and add producer logic)
- Modify: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` (replace scaffolding test, add real ones)

- [ ] **Step 1: Write failing tests for the real behavior.**

Replace the body of `CountdownV2Tests` with:

```swift
@Suite("CountdownV2")
struct CountdownV2Tests {

    @Test
    func `ticks - emits aligned countdown values at one-second cadence`() async {
        let (sut, _, clock, _) = makeSUT(startingAt: 0)

        let collected = Task { await sut.ticks.collect(3) }
        await Task.megaYield()
        await clock.advance(by: .seconds(3))
        let ticks = await collected.value

        #expect(ticks.map(\.value) == [29, 28, 27])
    }

    @Test
    func `ticks - reports windowChanged true on the first emission`() async {
        let (sut, _, clock, _) = makeSUT(startingAt: 0)

        let collected = Task { await sut.ticks.collect(1) }
        await Task.megaYield()
        await clock.advance(by: .seconds(1))
        let ticks = await collected.value

        #expect(ticks.first?.windowChanged == true)
    }

    @Test
    func `ticks - reports windowChanged true when crossing a window boundary`() async {
        // Start at t=27 so the boundary at t=30 falls inside the collected ticks.
        let (sut, _, clock, _) = makeSUT(startingAt: 27)

        let collected = Task { await sut.ticks.collect(5) }
        await Task.megaYield()
        await clock.advance(by: .seconds(5))
        let ticks = await collected.value

        // Tick 1 (t=28): windowChanged true (first emission).
        // Tick 2 (t=29): false.
        // Tick 3 (t=30): boundary crossed, true.
        // Tick 4 (t=31): false.
        // Tick 5 (t=32): false.
        #expect(ticks.map(\.windowChanged) == [true, false, true, false, false])
        #expect(ticks.map(\.value) == [2, 1, 30, 29, 28])
    }

    @Test
    func `ticks - multiple subscribers receive the same tick stream`() async {
        let (sut, _, clock, _) = makeSUT(startingAt: 0)

        let a = Task { await sut.ticks.collect(2) }
        let b = Task { await sut.ticks.collect(2) }
        await Task.megaYield()
        await clock.advance(by: .seconds(2))

        let aTicks = await a.value
        let bTicks = await b.value

        #expect(aTicks == bTicks)
        #expect(aTicks.count == 2)
    }

    @Test
    func `ticks - resumes correctly after all subscribers drop and a new one subscribes`() async {
        let (sut, _, clock, _) = makeSUT(startingAt: 0)

        // First subscription, collect 2 ticks then drop.
        let first = Task { await sut.ticks.collect(2) }
        await Task.megaYield()
        await clock.advance(by: .seconds(2))
        _ = await first.value

        // Allow termination handlers to run and producer to be torn down.
        await Task.megaYield()

        // Second subscription, collect 2 more ticks.
        let second = Task { await sut.ticks.collect(2) }
        await Task.megaYield()
        await clock.advance(by: .seconds(2))
        let secondTicks = await second.value

        // The second subscription should see windowChanged=true on its first tick
        // (lastWindow is reset when the producer torn down).
        #expect(secondTicks.count == 2)
        #expect(secondTicks.first?.windowChanged == true)
    }
}

private extension CountdownV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: CountdownV2, leak: LeakTracker, clock: TestClock<Duration>, date: DateBox) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let sut = CountdownV2(
            timeStep: timeStep,
            clock: clock,
            dateProvider: { dateBox.next() }
        )
        return (sut, trackForMemoryLeaks(sut, sourceLocation: sourceLocation), clock, dateBox)
    }
}

/// Sendable date provider that mints monotonically-increasing one-second steps.
/// Matches the cadence of `clock.timer(interval: .seconds(1))`.
private final class DateBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date())
    init(start: Date) {
        lock.withLock { $0 = start }
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

(Note: `DateBox` is `@unchecked Sendable` because the lock guarantees safety; this is acceptable inside test infrastructure even though production code follows the CLAUDE.md "no `@unchecked Sendable`" rule.)

Add `import os` at the top of the test file.

- [ ] **Step 2: Run the tests, expect failure.**

`RunSomeTests` filtered to `CountdownV2Tests`.
Expected: all four FAIL (the skeleton's empty `AsyncStream { _ in }` never yields).

- [ ] **Step 3: Implement `ticks` and the producer loop.**

Replace the `var ticks: AsyncStream<Tick>` definition in `CountdownV2.swift` with:

```swift
public var ticks: AsyncStream<Tick> {
    AsyncStream { continuation in
        let id = UUID()
        let needsStart = state.withLock { state -> Bool in
            state.subscribers[id] = continuation
            if state.producerTask == nil {
                return true
            }
            return false
        }

        if needsStart {
            startProducer()
        }

        continuation.onTermination = { [weak self] _ in
            self?.unsubscribe(id: id)
        }
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
        let clock = self.clock
        for await _ in clock.timer(interval: .seconds(1)) {
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

    for sub in subs {
        sub.yield(tick)
    }
}
```

- [ ] **Step 4: Run the tests, expect pass.**

`RunSomeTests` filtered to `CountdownV2Tests`.
Expected: all five tests PASS.

If a test is flaky, increase the `Task.megaYield(count:)` value (e.g. `await Task.megaYield(count: 50)`).

- [ ] **Step 5: Run the full suite to confirm no regression.**

`RunAllTests`.
Expected: all green (existing XCTest + new swift-testing).

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/CountdownV2.swift Tests/SwiftyOTPTests/CountdownV2Tests.swift
git commit -m "$(cat <<'EOF'
implement \`CountdownV2.ticks\` lazy producer with \`AsyncStream\` broadcast

producer task starts on first subscriber and is cancelled when the last
subscriber drops. state lives behind \`OSAllocatedUnfairLock\`. five
swift-testing cases cover cadence, window-change detection, multi-
subscriber fan-out, and producer teardown/restart.
EOF
)"
```

---

# Phase 2 — `OTPTimerV2` (`@MainActor @Observable`)

### Task 2.1: `OTPTimerV2` skeleton

**Files:**
- Create: `Sources/SwiftyOTP/Timer/OTPTimerV2.swift`

- [ ] **Step 1: Create `OTPTimerV2.swift` with the skeleton.**

```swift
//
//  OTPTimerV2.swift
//  SwiftyOTP
//
//  V2 of `OTPTimer` — `@MainActor @Observable`, consumes `CountdownV2.ticks`.
//  Renamed to `OTPTimer` at cutover (phase 4).
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
        if startsAutomatically {
            start()
        }
    }

    public func start() {
        // Implementation in Task 2.3.
    }

    public func stop() {
        // Implementation in Task 2.3.
    }

    deinit {
        // Cancellation is nonisolated; safe from deinit.
        consumerTask?.cancel()
    }
}
```

- [ ] **Step 2: Verify `TOTPProvider` is `Sendable`.**

Open `Sources/SwiftyOTP/Timer/TOTPProvider.swift`. If the protocol does not declare `: Sendable`, add it now:

```swift
public protocol TOTPProvider: Sendable {
    typealias OTP = String
    func otp(intervalSince1970: TimeInterval) -> OTP
}
```

This is a non-breaking refinement — concrete conformers already are `Sendable` once Phase 3 lands.

- [ ] **Step 3: Build.**

`BuildProject` — expect clean build (or warnings about unused `consumerTask`/`lastOTP`).

- [ ] **Step 4: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2.swift Sources/SwiftyOTP/Timer/TOTPProvider.swift
git commit -m "$(cat <<'EOF'
add \`OTPTimerV2\` skeleton and mark \`TOTPProvider\` Sendable

\`OTPTimerV2\` is \`@MainActor @Observable\` with two observable
properties (\`currentOTP\`, \`countdown\`) plus \`start\`/\`stop\`.
producer integration lands in the next task.
EOF
)"
```

### Task 2.2: First `OTPTimerV2` tests — initial state

**Files:**
- Create: `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift`

- [ ] **Step 1: Write the failing tests.**

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
struct OTPTimerV2Tests {

    @Test
    func `currentOTP - is empty before any tick is consumed`() async {
        let (sut, _, _, _) = makeSUT(startsAutomatically: false)

        #expect(sut.currentOTP == "")
        #expect(sut.countdown == 0)
    }

    @Test
    func `init - exposes timeStep from the countdown source`() async {
        let (sut, _, _, _) = makeSUT(timeStep: 60, startsAutomatically: false)

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
    ) -> (sut: OTPTimerV2, leak: LeakTracker, clock: TestClock<Duration>, spy: OTPProviderSpy) {
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
        return (sut, trackForMemoryLeaks(sut, sourceLocation: sourceLocation), clock, spy)
    }
}

final class OTPProviderSpy: TOTPProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    func otp(intervalSince1970: TimeInterval) -> OTP {
        lock.withLock { count in
            defer { count += 1 }
            return "\(count)"
        }
    }
}

private final class DateBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date())
    init(start: Date) {
        lock.withLock { $0 = start }
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

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `OTPTimerV2Tests`.
Expected: PASS — both initial-state tests pass against the skeleton (since `start`/`stop` are no-ops).

- [ ] **Step 3: Commit.**

```bash
git add Tests/SwiftyOTPTests/OTPTimerV2Tests.swift
git commit -m "scaffold \`OTPTimerV2Tests\` with initial-state assertions"
```

### Task 2.3: Implement `start`/`stop` consumer loop

**Files:**
- Modify: `Sources/SwiftyOTP/Timer/OTPTimerV2.swift`
- Modify: `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` (add behavior tests)

- [ ] **Step 1: Write failing tests for start/stop behavior.**

Append inside `struct OTPTimerV2Tests`:

```swift
@Test
func `start - updates currentOTP from provider on first tick`() async {
    let (sut, _, clock, _) = makeSUT()

    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    await Task.megaYield()

    #expect(sut.currentOTP == "0")
}

@Test
func `currentOTP - changes only when the window boundary is crossed`() async {
    let (sut, _, clock, _) = makeSUT(startingAt: 27)

    await Task.megaYield()
    // Tick 1 (t=28, windowChanged=true) → otp "0"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let firstOTP = sut.currentOTP

    // Tick 2 (t=29, windowChanged=false) → still "0"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let sameWindowOTP = sut.currentOTP

    // Tick 3 (t=30, windowChanged=true) → otp "1"
    await clock.advance(by: .seconds(1))
    await Task.megaYield()
    let nextWindowOTP = sut.currentOTP

    #expect(firstOTP == "0")
    #expect(sameWindowOTP == "0")
    #expect(nextWindowOTP == "1")
}

@Test
func `countdown - mirrors the latest tick value`() async {
    let (sut, _, clock, _) = makeSUT(startingAt: 0)

    await Task.megaYield()
    await clock.advance(by: .seconds(3))
    await Task.megaYield()

    // Last tick at t=3 → countdown = 30 - 3 = 27.
    #expect(sut.countdown == 27)
}

@Test
func `start - is idempotent when called twice`() async {
    let (sut, _, clock, spy) = makeSUT(startsAutomatically: false)

    sut.start()
    sut.start()

    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    await Task.megaYield()

    // Only one consumer task means provider is called once on the first tick.
    #expect(sut.currentOTP == "0")
    _ = spy   // keep alive
}

@Test
func `stop - stops updating observable state`() async {
    let (sut, _, clock, _) = makeSUT(startingAt: 0)

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

- [ ] **Step 2: Run the new tests, expect failure.**

`RunSomeTests` filtered to `OTPTimerV2Tests`.
Expected: the new tests FAIL (`currentOTP` stays empty because `start`/`stop` are no-ops).

- [ ] **Step 3: Implement `start` and `stop`.**

In `OTPTimerV2.swift`, replace the empty `start()` and `stop()` bodies:

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

The `Task { ... }` closure inherits `@MainActor` isolation from the enclosing class because `start()` is `@MainActor` (the class is). The `for await` body therefore mutates `currentOTP`/`countdown` on `MainActor`. If the compiler complains, mark the closure explicitly: `Task { @MainActor [weak self] in ... }`.

- [ ] **Step 4: Run the tests, expect pass.**

`RunSomeTests` filtered to `OTPTimerV2Tests`.
Expected: all tests PASS.

- [ ] **Step 5: Run the full suite.**

`RunAllTests` — expect green.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2.swift Tests/SwiftyOTPTests/OTPTimerV2Tests.swift
git commit -m "$(cat <<'EOF'
implement \`OTPTimerV2.start\`/\`stop\` consumer loop

a single consumer task subscribes to \`CountdownV2.ticks\` and updates
\`currentOTP\` and \`countdown\` on \`MainActor\`. otp recomputation
only happens on window changes; \`start\` is idempotent; \`stop\`
cancels the consumer task.
EOF
)"
```

### Task 2.4: `OTPTimerV2+TOTPGenerator` convenience inits

**Files:**
- Create: `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift`

- [ ] **Step 1: Create the file with full contents.**

```swift
//
//  OTPTimerV2+TOTPGenerator.swift
//  SwiftyOTP
//

import Foundation

public extension OTPTimerV2 {
    /// Convenience initialiser for `OTPTimerV2` with a custom `TOTPGenerator`.
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

    /// Convenience initialiser building a `TOTPGenerator` from a seed.
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

If `TOTPGenerator: TOTPProvider` conformance lives in the soon-to-be-removed `OTPTimer+TOTPGenerator.swift`, that's fine — it stays until cutover. The conformance line is `extension TOTPGenerator: TOTPProvider {}` in that file.

- [ ] **Step 3: Commit.**

```bash
git add Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift
git commit -m "add \`OTPTimerV2\` convenience initialisers for \`TOTPGenerator\` and \`Seed\`"
```

### Task 2.5: `OTPTimerV2` integration test with real `TOTPGenerator`

**Files:**
- Create: `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
//
//  OTPTimerV2IntegrationTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import Clocks
@testable import SwiftyOTP

@MainActor
@Suite("OTPTimerV2 integration")
struct OTPTimerV2IntegrationTests {

    /// RFC 6238 SHA-1 test seed.
    private var seedSha1: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `currentOTP - matches RFC 6238 vectors across a window boundary`() async throws {
        // RFC 6238 vector at t=59 → 94287082 (8-digit SHA-1 OTP).
        // Start at t=28 so the 30s boundary at t=30 is crossed.
        let (sut, _, clock) = try makeSUT(startingAt: 28)

        await Task.megaYield()
        // Tick 1: t=29, window 0 → otp 84755224
        // Tick 2: t=30, window 1 → otp 94287082
        await clock.advance(by: .seconds(2))
        await Task.megaYield()

        #expect(sut.currentOTP == "94287082")
    }
}

@MainActor
private extension OTPTimerV2IntegrationTests {
    func makeSUT(
        startingAt secondsSinceEpoch: TimeInterval,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (sut: OTPTimerV2, leak: LeakTracker, clock: TestClock<Duration>) {
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
        return (sut, trackForMemoryLeaks(sut, sourceLocation: sourceLocation), clock)
    }
}
```

(Note: this test imports `DateBox` from `OTPTimerV2Tests.swift`'s file scope. If linker issues arise, copy `DateBox` here too — it's tiny test infrastructure.)

If `DateBox` is `private` to its file, copy it into this file as well (private to this file). Same for `OSAllocatedUnfairLock` `import os`.

- [ ] **Step 2: Run the test.**

`RunSomeTests` filtered to `OTPTimerV2IntegrationTests`.
Expected: PASS — `OTPTimerV2`'s consumer loop produces the correct RFC OTP.

- [ ] **Step 3: Run the full suite.**

`RunAllTests` — expect green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift
git commit -m "verify \`OTPTimerV2\` against RFC 6238 SHA-1 test vector across a window boundary"
```

---

# Phase 3 — Generators: `Sendable` annotations + test migration

Generator types are already structs so `Sendable` is mostly a declaration. Test files migrate in place because there's no V2 to swap to.

### Task 3.1: `Sendable` on generators

**Files:**
- Modify: `Sources/SwiftyOTP/Generators/HashingAlgorithm.swift`
- Modify: `Sources/SwiftyOTP/Generators/Seed.swift`
- Modify: `Sources/SwiftyOTP/Generators/HOTPGenerator.swift`
- Modify: `Sources/SwiftyOTP/Generators/TOTPGenerator.swift`

- [ ] **Step 1: `HashingAlgorithm.swift` — add `Sendable`.**

Change the declaration:

```swift
public enum HashingAlgorithm: Sendable {
    case sha1
    case sha256
    case sha512
}
```

- [ ] **Step 2: `Seed.swift` — add `Sendable`.**

Change the declaration:

```swift
public enum Seed: Sendable {
    case base64(String)
    case base32(String)
    case hex(String)
    case data(Data)
    // ... rest unchanged
}
```

- [ ] **Step 3: `HOTPGenerator.swift` — add `Sendable`.**

Change the struct declaration:

```swift
public struct HOTPGenerator: Sendable {
    // ... rest unchanged
}
```

- [ ] **Step 4: `TOTPGenerator.swift` — add `Sendable` and mark stored closure `@Sendable`.**

```swift
public struct TOTPGenerator: Sendable {
    var currentDateProvider: @Sendable () -> Date = { Date() }
    // ... rest unchanged (do NOT change `Date.init` to `{ Date() }` elsewhere; this line is the only change in this property)
}
```

The `currentDateProvider` default was previously `Date.init` (which is `@Sendable`-compatible) — explicitly marking the property type clarifies intent and lets the compiler enforce.

- [ ] **Step 5: Build to verify.**

`BuildProject`. Expected: clean build, no Sendable warnings on generators.

- [ ] **Step 6: Commit.**

```bash
git add Sources/SwiftyOTP/Generators/
git commit -m "$(cat <<'EOF'
mark generator types \`Sendable\`

\`HashingAlgorithm\`, \`Seed\`, \`HOTPGenerator\`, and \`TOTPGenerator\`
become explicitly \`Sendable\`. \`TOTPGenerator.currentDateProvider\`
gains an explicit \`@Sendable\` annotation so concurrency checks pass
once strict mode is re-enabled.
EOF
)"
```

### Task 3.2: Migrate `HOTPGeneratorTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/HOTPGeneratorTests.swift` (replace contents)

- [ ] **Step 1: Replace contents.**

```swift
//
//  HOTPGeneratorTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("HOTPGenerator")
struct HOTPGeneratorTests {

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
            try HOTPGenerator(seed: .data(seedData), digits: 5)
        }
    }

    @Test
    func `init - throws when digits is above the valid range`() {
        #expect(throws: (any Error).self) {
            try HOTPGenerator(seed: .data(seedData), digits: 9)
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

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `HOTPGeneratorTests`.
Expected: PASS.

- [ ] **Step 3: Run full suite.**

`RunAllTests` — expect green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/HOTPGeneratorTests.swift
git commit -m "migrate \`HOTPGeneratorTests\` to swift-testing"
```

### Task 3.3: Migrate `TOTPGeneratorTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/TOTPGeneratorTests.swift` (replace contents wholesale)

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
struct TOTPGeneratorTests {

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
            (UInt64(59), "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130"),
        ]
    )
    func sha1Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha1, algo: .sha1)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-256 vectors",
        arguments: [
            (UInt64(59), "46119246"),
            (1111111109, "68084774"),
            (1111111111, "67062674"),
            (1234567890, "91819424"),
            (2000000000, "90698825"),
            (20000000000, "77737706"),
        ]
    )
    func sha256Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha256, algo: .sha256)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-512 vectors",
        arguments: [
            (UInt64(59), "90693936"),
            (1111111109, "25091201"),
            (1111111111, "99943326"),
            (1234567890, "93441116"),
            (2000000000, "38618901"),
            (20000000000, "47863826"),
        ]
    )
    func sha512Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha512, algo: .sha512)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }
}
```

(Note: parameterised `@Test` requires `arguments` arrays whose element types conform to `Sendable`. Tuples of `UInt64` and `String` qualify. The function name `sha1Vector` is the required identifier; the suite display name `"otp(unixTimestamp:) - matches RFC 6238 SHA-1 vectors"` is the human-readable label shown in the test navigator.)

- [ ] **Step 2: Run the tests.**

`RunSomeTests` filtered to `TOTPGeneratorTests`.
Expected: PASS for every test (2 throwing + 1 cross-algorithm + 6+6+6 parameterised vectors = 21 cases).

- [ ] **Step 3: Run full suite.**

`RunAllTests` — expect green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/TOTPGeneratorTests.swift
git commit -m "migrate \`TOTPGeneratorTests\` to swift-testing with parameterised RFC 6238 vectors"
```

### Task 3.4: Migrate `SeedTests` to swift-testing

**Files:**
- Modify: `Tests/SwiftyOTPTests/SeedTests.swift` (replace contents wholesale)

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
struct SeedTests {

    private var dataSeed: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `data() - hex encoding decodes to the expected bytes`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.hex("3132333435363738393031323334353637383930")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - hex encoding throws on invalid hex`() {
        let invalid = "3132333435363738393031323334353637383930Z"
        let sut = Seed.hex(invalid)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base32 encoding decodes to the expected bytes`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - base32 encoding throws on invalid base32`() {
        let invalid = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ1"
        let sut = Seed.base32(invalid)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base64 encoding decodes to the expected bytes`() throws {
        let expected = try Seed.data(dataSeed).data()
        let sut = Seed.base64("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - base64 encoding throws on invalid base64`() {
        let invalid = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=!"
        let sut = Seed.base64(invalid)
        #expect(throws: (any Error).self) { try sut.data() }
    }
}
```

- [ ] **Step 2: Run.**

`RunSomeTests` filtered to `SeedTests`.
Expected: 6 tests PASS.

- [ ] **Step 3: Run full suite.**

`RunAllTests` — expect green.

- [ ] **Step 4: Commit.**

```bash
git add Tests/SwiftyOTPTests/SeedTests.swift
git commit -m "migrate \`SeedTests\` to swift-testing"
```

---

# Phase 4 — Cutover

Single phase, single commit. Removes the old API, renames V2 → final, re-enables strict concurrency, fixes any straggler diagnostics.

### Task 4.1: Delete legacy source and test files

**Files:**
- Delete: `Sources/SwiftyOTP/Timer/Countdown.swift`
- Delete: `Sources/SwiftyOTP/Timer/OTPTimer.swift`
- Delete: `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift`
- Delete: `Tests/SwiftyOTPTests/CountdownTests.swift`
- Delete: `Tests/SwiftyOTPTests/OTPTimerTests.swift`
- Delete: `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift`
- Delete: `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
- Delete: `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
- Delete: `Tests/SwiftyOTPTests/Helper/DateProvider.swift`

- [ ] **Step 1: Delete legacy files.**

```bash
rm Sources/SwiftyOTP/Timer/Countdown.swift \
   Sources/SwiftyOTP/Timer/OTPTimer.swift \
   Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift \
   Tests/SwiftyOTPTests/CountdownTests.swift \
   Tests/SwiftyOTPTests/OTPTimerTests.swift \
   Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift \
   Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift \
   Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift \
   Tests/SwiftyOTPTests/Helper/DateProvider.swift
```

- [ ] **Step 2: Verify no remaining references.**

```bash
git grep -nE "Countdown\b|\bOTPTimer\b|XCTestCase|XCTAssert" Sources Tests
```

Expected: every hit is in a `*V2*` file (about to be renamed) or in a comment in `LeakTracker`/`AsyncStreamCollect`. No `XCTAssert*` or `XCTestCase` should remain.

If a hit shows up in V2 files, that means a V2 file is calling the *old* `Countdown` or `OTPTimer` type — fix it to call its V2 counterpart before proceeding.

(Do NOT commit yet — the build is broken because V2 code still uses `CountdownV2`/`OTPTimerV2` names. Continue to next task.)

### Task 4.2: Rename V2 files and types

**Files:**
- Rename: `Sources/SwiftyOTP/Timer/CountdownV2.swift` → `Sources/SwiftyOTP/Timer/Countdown.swift`
- Rename: `Sources/SwiftyOTP/Timer/OTPTimerV2.swift` → `Sources/SwiftyOTP/Timer/OTPTimer.swift`
- Rename: `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift` → `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift`
- Rename: `Tests/SwiftyOTPTests/CountdownV2Tests.swift` → `Tests/SwiftyOTPTests/CountdownTests.swift`
- Rename: `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` → `Tests/SwiftyOTPTests/OTPTimerTests.swift`
- Rename: `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift` → `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift`

- [ ] **Step 1: Move the files.**

```bash
git mv Sources/SwiftyOTP/Timer/CountdownV2.swift Sources/SwiftyOTP/Timer/Countdown.swift
git mv Sources/SwiftyOTP/Timer/OTPTimerV2.swift Sources/SwiftyOTP/Timer/OTPTimer.swift
git mv Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift
git mv Tests/SwiftyOTPTests/CountdownV2Tests.swift Tests/SwiftyOTPTests/CountdownTests.swift
git mv Tests/SwiftyOTPTests/OTPTimerV2Tests.swift Tests/SwiftyOTPTests/OTPTimerTests.swift
git mv Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift
```

- [ ] **Step 2: Rename type identifiers and `@Suite` titles.**

For each renamed file, replace every occurrence of `CountdownV2` → `Countdown` and `OTPTimerV2` → `OTPTimer`. Also update `@Suite("CountdownV2")` → `@Suite("Countdown")` and `@Suite("OTPTimerV2")` → `@Suite("OTPTimer")`.

```bash
# Sources
sed -i '' 's/CountdownV2/Countdown/g' Sources/SwiftyOTP/Timer/Countdown.swift
sed -i '' 's/OTPTimerV2/OTPTimer/g'   Sources/SwiftyOTP/Timer/OTPTimer.swift
sed -i '' 's/OTPTimerV2/OTPTimer/g'   Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift

# Tests
sed -i '' 's/CountdownV2/Countdown/g' Tests/SwiftyOTPTests/CountdownTests.swift
sed -i '' 's/OTPTimerV2/OTPTimer/g'   Tests/SwiftyOTPTests/OTPTimerTests.swift
sed -i '' 's/OTPTimerV2/OTPTimer/g'   Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift
```

Also remove file-header comments that say "V2 of `Countdown`" or "Renamed at cutover" — those are now obsolete. Replace each with a one-line file comment, or delete the header.

- [ ] **Step 3: Verify no `*V2*` identifier remains.**

```bash
git grep -nE "CountdownV2|OTPTimerV2" Sources Tests
```

Expected: zero hits.

- [ ] **Step 4: Build.**

`BuildProject`. Expected: clean build (still under approachable concurrency).

- [ ] **Step 5: Run all tests.**

`RunAllTests`. Expected: every swift-testing suite green.

(Still no commit — Package.swift change comes next.)

### Task 4.3: Re-enable strict concurrency

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Replace the `upcomingFeatures` array in `Package.swift`.**

Replace the relaxed-concurrency block:

```swift
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
]
```

with:

```swift
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]
```

If `swiftLanguageModes` was downgraded to `.v5` in Phase 0, restore `swiftLanguageModes: [.v6]` here.

- [ ] **Step 2: Build.**

`BuildProject`. Expected behaviour:
- Best case: clean build with strict concurrency. Move on.
- Likely case: a small number of strict-concurrency diagnostics surface (Sendable, isolation, closure-capture warnings). Fix each one in the next task.

- [ ] **Step 3: If diagnostics surfaced, fix them in place.**

For each diagnostic, apply the smallest fix that resolves it without violating CLAUDE.md (no `@unchecked Sendable` in production code, no `@preconcurrency` on imports unless absolutely required). Common patterns and their fixes:

| Diagnostic | Fix |
|---|---|
| `Capture of 'self' with non-sendable type 'OTPTimer' in a `@Sendable` closure` | The class is `@MainActor`; the closure needs to inherit isolation. Change `Task { [weak self] in ... }` → `Task { @MainActor [weak self] in ... }`. |
| `Stored property 'X' of 'Sendable'-conforming class 'OTPTimer' is mutable` | Already `@MainActor`-isolated, so this should not fire on `OTPTimer`. If it does, audit: any `@ObservationIgnored` mutable property must be touched only on `MainActor`. |
| `Capture of non-sendable type in '@Sendable' closure (Countdown producer)` | The producer task captures `self.clock` (an `any Clock<Duration>`). Since `Clock` requires `Instant: InstantProtocol & Sendable`, all conforming clocks are `Sendable` — this should be fine. If it fires, capture into a local: `let clock = self.clock; Task { ... clock.timer(...) ... }`. |

- [ ] **Step 4: Run all tests.**

`RunAllTests`. Expected: green.

- [ ] **Step 5: Final verification.**

```bash
git grep -nE "Combine|Foundation\\.Timer|ObservableObject|XCTest" Sources Tests
```

Expected: zero hits in `Sources`. In `Tests`, the only hits should be in helper file headers/comments (not actual `import XCTest` statements). If `import XCTest` remains anywhere, fix it.

```bash
git grep -nE "XCTAssert|@unchecked Sendable" Sources
```

Expected: zero hits in `Sources`. (`@unchecked Sendable` is permitted in test infrastructure per task 1.6 / 2.2 but never in production code.)

### Task 4.4: Single cutover commit

- [ ] **Step 1: Stage everything.**

```bash
git add -A
git status
```

Verify the diff: deletions of legacy files, renames `V2 → final`, `Package.swift` upcoming-features swap, plus any concurrency fixes from task 4.3.

- [ ] **Step 2: Commit.**

```bash
git commit -m "$(cat <<'EOF'
cut over to \`@Observable\` \`OTPTimer\` and \`Sendable\` \`Countdown\`

deletes the combine + \`Foundation.Timer\` legacy implementations of
\`Countdown\`, \`OTPTimer\`, and their xctest suites. renames the V2
counterparts into place. re-enables strict concurrency in
\`Package.swift\` (replacing the approachable-concurrency upcoming-
feature set introduced in phase 0).

closes the migration designed in
docs/superpowers/specs/2026-04-24-swift6-observation-swiftclocks-migration-design.md
EOF
)"
```

- [ ] **Step 3: Post-cutover verification.**

```bash
BuildProject              # expect clean
RunAllTests               # expect green
git grep -nE "V2|Combine|Foundation\\.Timer|ObservableObject|XCTest" Sources
git grep -nE "import XCTest|XCTAssert" Tests
```

Expected:
- Build clean. All tests green.
- The first grep returns no source-code hits (only spec/plan markdown matches, which are fine).
- The second grep returns zero hits.

Migration complete.

---

## Out of scope (tracked here for later)

- **Phase 5** from the spec: updating `code-keeper-authenticator` (`OTPViewModel` → `@Observable`, removing `OTPCodeProvider` indirection). Separate brainstorm + plan in that repo when this lands.
- DocC documentation refresh.
- Tag/release of the new major version on GitHub.
