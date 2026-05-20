# SwiftyOTP — Swift 6 / Observation / swift-clocks migration

Date: 2026-05-20
Status: design (pending implementation plan)
Branch: `chore/swift-6-migration`
Supersedes: a prior 2026-04-24 spec + plan and the `migration/swift6-observation-swiftclocks` branch, both written from scratch and discarded in favor of this version.

## Goal

Migrate `SwiftyOTP` from Combine + `Foundation.Timer` + XCTest to:

- Strict Swift 6 concurrency, every public type `Sendable`, no `@unchecked Sendable` in production code.
- `Countdown` as a `final class Sendable` driven by `swift-clocks`, broadcasting `Tick` values via `AsyncStream` with multi-subscriber fan-out and lazy producer lifecycle.
- `OTPTimer` as a `@MainActor @Observable final class` exposing `currentOTP: String` and `countdown: TimeInterval` as direct observed properties.
- `Combine` import removed from the package entirely.
- All tests on swift-testing, suites as `final class` subclasses of a `LeakTrackingTestCase` base, with `addTeardownBlock` + `deinit` driving memory-leak assertions (Ricky Munz pattern).

This is a **major version, breaking change**. Platforms bump to **iOS 17 / macOS 14** (required by Observation).

## Non-goals

- Updating `code-keeper-authenticator` (tracked as a follow-up).
- New OTP features (URI parsing, keychain helpers, additional algorithms).
- A deprecation window for the old `.publisher` API — clean break.
- DocC tooling beyond inline doc comments.
- Performance work beyond what naturally falls out of the rewrite.
- CI configuration changes.

## Scope decisions

These are the decisions made during brainstorming and are now fixed:

1. **Platform minimums = iOS 17 / macOS 14.** Already in `Package.swift` on the current branch. Driven by Observation framework.
2. **Side-by-side V2 migration** with single-commit cutover. The old types compile and pass tests until the cutover commit replaces them.
3. **`Countdown` fans out to multiple subscribers with a shared cadence.** One producer task per Countdown instance, broadcasting one Tick to every subscriber. Justified by the consumer pattern in `code-keeper-authenticator`, where one shared `Countdown` synchronizes ticking across many displayed OTP rows.
4. **Tick delivery via `AsyncStream<Tick>`.** Each call to `.ticks` returns a fresh stream backed by an internal continuation. No `Combine`, no third-party broadcast library.
5. **Lazy lifecycle.** No public `start()`/`stop()` on `Countdown`. The producer task spawns on the first subscriber and is cancelled when the last drops.
6. **`final class Countdown: Sendable` + `OSAllocatedUnfairLock<State>`.** Lock chosen over `Synchronization.Mutex` (iOS 18+) and over `actor` (async-only API). Internal state mutations (subscribe / unsubscribe / tick) come from different tasks; the lock serializes them with minimal cost.
7. **`@MainActor @Observable final class OTPTimer`.** SwiftUI is the dominant consumer. The internal consumer task inherits `@MainActor` from the enclosing class, so observed-property writes are main-actor safe by construction.
8. **OTPTimer exposes direct observed properties** (`currentOTP: String`, `countdown: TimeInterval`). The old `OTPTimer.Event` struct is deleted.
9. **`start()`/`stop()` on `OTPTimer` are preserved**, defaulting to `startsAutomatically: true` for parity with the old API. `start()` is idempotent. `stop()` cancels the consumer task.
10. **Generators (`HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPDigitsChecker`) get `Sendable` conformance only.** No structural changes. `TOTPGenerator.currentDateProvider` becomes `@Sendable () -> Date`.
11. **`Tick` is a top-level public type**, not nested inside `Countdown`. The package's primary value type — discoverability beats namespacing.
12. **Tests use `@Suite final class` shape, inheriting from `LeakTrackingTestCase`** — a non-final base class with `addTeardownBlock` and a `trackForMemoryLeaks(_:)` helper. Per-test instances mean `deinit` fires per test.
13. **No deprecation period** for the old `.publisher` API. Pre-cutover, both APIs coexist (V2 additive). Post-cutover, the old API is gone.
14. **Single-commit cutover** at the end: delete the old types and old XCTest helpers, rename `*V2` → final names, re-enable `.enableUpcomingFeature("StrictConcurrency")`.
15. **The 2026-04-24 spec and plan are deleted** in the same commit that adds this spec. The `migration/swift6-observation-swiftclocks` branch is left alone (not deleted).

## Component shapes

### `Tick` (new)

```swift
public struct Tick: Sendable, Equatable {
    public let value: TimeInterval     // seconds remaining in the current window
    public let date: Date              // when the tick was produced
    public let windowChanged: Bool     // true on first tick and at every window boundary

    public init(value: TimeInterval, date: Date, windowChanged: Bool)
}
```

### `Countdown` (rewritten)

```swift
public final class Countdown: Sendable {
    public let timeStep: UInt

    public init(
        timeStep: UInt,
        clock: any Clock<Duration> = ContinuousClock(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    )

    public var ticks: AsyncStream<Tick> { get }
}
```

**Internal**:

```swift
private struct State {
    var subscribers: [UUID: AsyncStream<Tick>.Continuation] = [:]
    var producerTask: Task<Void, Never>?
    var lastWindow: UInt?
}

private let state = OSAllocatedUnfairLock<State>(initialState: State())
private let clock: any Clock<Duration>
private let dateProvider: @Sendable () -> Date
```

**Invariants the lock protects**:
1. (Subscriber-insertion, producer-spawn) pair is atomic. Two simultaneous first-subscribers can't both spawn producers.
2. (Subscriber-removal, producer-cancel) pair is atomic. After the producer is cancelled, no further ticks can be broadcast.
3. `lastWindow` updates happen-before the `windowChanged` value derived from them is yielded.

**Subscribe path** (inside the `AsyncStream` builder):

```swift
let id = UUID()
let needsStart = state.withLock { state -> Bool in
    state.subscribers[id] = continuation
    if state.producerTask == nil { return true }
    return false
}
if needsStart { startProducer() }
continuation.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
```

**Unsubscribe path**:

```swift
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
```

**Producer body**:

```swift
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

    for sub in subs { sub.yield(tick) }    // yield outside the lock
}
```

### `OTPTimer` (rewritten)

```swift
@MainActor
@Observable
public final class OTPTimer {
    public let timeStep: UInt
    public private(set) var currentOTP: String = ""
    public private(set) var countdown: TimeInterval = 0

    @ObservationIgnored private let countdownSource: Countdown
    @ObservationIgnored private let totpProvider: any TOTPProvider
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var lastOTP: String?

    public init(
        countdown: Countdown,
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

    deinit { consumerTask?.cancel() }   // cancellation is nonisolated
}
```

The `Task { [weak self] in ... }` closure inherits `@MainActor` from the enclosing class. If the compiler reports otherwise, mark explicitly: `Task { @MainActor [weak self] in ... }`.

### `TOTPProvider` (refined)

```swift
public protocol TOTPProvider: Sendable {
    typealias OTP = String
    func otp(intervalSince1970: TimeInterval) -> OTP
}
```

### `OTPTimer+TOTPGenerator` (rewritten)

```swift
public extension OTPTimer {
    convenience init(
        totpGenerator: TOTPGenerator,
        timeStep: UInt = 30,
        startsAutomatically: Bool = true
    ) {
        self.init(
            countdown: Countdown(timeStep: timeStep),
            totpProvider: totpGenerator,
            startsAutomatically: startsAutomatically
        )
    }

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
            countdown: Countdown(timeStep: timeStep),
            totpProvider: provider,
            startsAutomatically: startsAutomatically
        )
    }
}
```

The `interval` parameter is dropped — `Countdown` always ticks at 1 Hz now.

### Generators

In-place additions only:

- `HashingAlgorithm: Sendable`
- `Seed: Sendable`
- `HOTPGenerator: Sendable`
- `TOTPGenerator: Sendable`, `currentDateProvider: @Sendable () -> Date`
- `OTPDigitsChecker` — internal, unchanged

## Data flow

```
SwiftUI view
  │ observes (Observation framework)
  ▼
OTPTimer  (@MainActor @Observable final class)
  ├─ currentOTP: String         ← observed
  ├─ countdown: TimeInterval    ← observed
  └─ consumerTask: Task { @MainActor in
        for await tick in countdown.ticks {
            if tick.windowChanged || lastOTP == nil {
                lastOTP = totpProvider.otp(intervalSince1970: tick.date.timeIntervalSince1970)
            }
            currentOTP = lastOTP
            countdown = tick.value
        }
     }
                │ awaits
                ▼
Countdown  (final class Sendable, OSAllocatedUnfairLock<State>)
  ├─ State { subscribers, producerTask, lastWindow }
  │
  ├─ ticks → AsyncStream { continuation in
  │      register continuation under new UUID;
  │      if subscribers was empty, spawn producer;
  │      onTermination → unsubscribe }
  │
  └─ producer task
        for await _ in clock.timer(interval: .seconds(1)) {
            broadcastTick()
        }
```

**Cancellation propagation**:
- `OTPTimer.stop()` cancels the consumer task → its `for await` ends → its `AsyncStream` iterator deinit fires → `continuation.onTermination` runs → Countdown's `unsubscribe(id)` removes the entry → (if last) producer task cancelled.
- `OTPTimer.deinit` does the same via `consumerTask?.cancel()`.
- `Countdown` has no `deinit` cancellation. If a subscriber's `Task` is still iterating, its iterator holds the stream alive, which holds the continuation; the continuation captures `[weak self]` only, so `Countdown` can deinit while subscribers exist — their iterators terminate naturally.

## Test infrastructure

### `LeakTrackingTestCase`

```swift
import Testing

/// Base class for swift-testing suites that need memory-leak assertions.
/// Suites subclass this and call `trackForMemoryLeaks(_:)` on any reference
/// types they want to assert get deallocated by end of test.
/// Per swift-testing, each `@Test` runs on a fresh instance, so `deinit`
/// fires per-test. Single-threaded by contract: do not call `addTeardownBlock`
/// from background tasks.
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

### Suite shape (non-isolated case)

```swift
@Suite("Countdown")
final class CountdownTests: LeakTrackingTestCase {

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

private extension CountdownTests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: Countdown, clock: TestClock<Duration>, date: DateBox) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let sut = Countdown(timeStep: timeStep, clock: clock, dateProvider: { dateBox.next() })
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock, dateBox)
    }
}
```

### Suite shape (`@MainActor` case)

```swift
@MainActor
@Suite("OTPTimer")
final class OTPTimerTests: LeakTrackingTestCase {
    // ...
}
```

Base class is non-isolated. Subclass is `@MainActor`. Inherited methods are non-isolated but only called from the `@MainActor` subclass body, which is fine.

### Helpers

Three internal helpers in `Tests/SwiftyOTPTests/Helper/`:

- **`LeakTrackingTestCase.swift`** — the class above.
- **`AsyncStreamCollect.swift`** — `extension AsyncSequence where Element: Sendable { func collect(_ count: Int) async rethrows -> [Element] }`.
- **`TaskMegaYield.swift`** — `static func megaYield(count: Int = 20) async` to drain cooperative scheduling so producer tasks reach their first `clock.timer` suspension before `clock.advance`.
- **`DateBox.swift`** — `final class DateBox: @unchecked Sendable` wrapping an `OSAllocatedUnfairLock<Date>` that hands out monotonically-increasing one-second steps. Test-only; doc-commented to forbid copying into Sources/.

### Naming convention (from `CLAUDE.md`)

```swift
@Test
func `<member> - <expected behavior>`() {
    let model = makeSUT()
    #expect(...)
}
```

Backticked identifier with a dash separator. Use `@Test` alone for self-describing functions; use `@Test("…")` only for parameterized tests that need a separate label.

### Files deleted at cutover

- `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
- `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
- `Tests/SwiftyOTPTests/Helper/DateProvider.swift`

## Phasing

Each phase is a self-contained commit (or PR). The test suite stays green throughout. `Package.swift` on `chore/swift-6-migration` already declares iOS 17 / macOS 14, swift-clocks 1.0.6, and the approachable-concurrency upcoming-feature set — no preparatory phase needed.

### Phase 1 — Test helpers

The obsolete 2026-04-24 spec and plan are deleted in the same commit that adds this spec, so Phase 1 only adds new helper files:

- Add `Tests/SwiftyOTPTests/Helper/LeakTrackingTestCase.swift`.
- Add `Tests/SwiftyOTPTests/Helper/AsyncStreamCollect.swift`.
- Add `Tests/SwiftyOTPTests/Helper/TaskMegaYield.swift`.
- Add `Tests/SwiftyOTPTests/Helper/DateBox.swift`.

Old XCTest helpers (`OTPTimerTestCase`, `XCTestCase+MemoryLeakTracking`, `DateProvider`) are untouched. Old XCTest suites keep using them.

**Acceptance**: `BuildProject` clean. `RunAllTests` green (legacy XCTest suite passes — no behavior changed).

### Phase 2 — `CountdownV2`

New files:
- `Sources/SwiftyOTP/Timer/CountdownV2.swift` — `final class CountdownV2: Sendable` with the `Tick` value type at top level, lock-protected state, lazy producer.
- `Tests/SwiftyOTPTests/CountdownV2Tests.swift` — `@Suite("CountdownV2") final class CountdownV2Tests: LeakTrackingTestCase`.

Test coverage (each test backticked per the naming convention):
- `ticks - emits aligned countdown values at one-second cadence`
- `ticks - reports windowChanged true on the first emission`
- `ticks - reports windowChanged true when crossing a window boundary`
- `ticks - multiple subscribers receive the same tick stream`
- `ticks - resumes correctly after all subscribers drop and a new one subscribes`

`TestClock.advance(by:)` drives time; `await Task.megaYield()` before each advance; `await sut.ticks.collect(N)` pulls values.

**Acceptance**: New tests green. Old `Countdown` + XCTest tests still green.

### Phase 3 — `OTPTimerV2` + convenience inits + integration

New files:
- `Sources/SwiftyOTP/Timer/OTPTimerV2.swift` — `@MainActor @Observable final class OTPTimerV2`.
- `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift` — convenience initialisers.
- `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` — `@MainActor @Suite("OTPTimerV2") final class OTPTimerV2Tests: LeakTrackingTestCase`.
- `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift` — integration with real `TOTPGenerator` + RFC 6238 vectors.

Modified:
- `Sources/SwiftyOTP/Timer/TOTPProvider.swift` — `+ Sendable` on the protocol.

Test coverage (unit):
- `currentOTP - is empty before any tick is consumed`
- `init - exposes timeStep from the countdown source`
- `start - updates currentOTP from provider on first tick`
- `currentOTP - changes only when the window boundary is crossed`
- `countdown - mirrors the latest tick value`
- `start - is idempotent when called twice`
- `stop - stops updating observable state`

Integration:
- `currentOTP - matches RFC 6238 vectors across a window boundary` (e.g. `94287082` at t=59 with seed `12345678901234567890`).

The unit suite uses an `OTPProviderSpy` (sendable, returns `"\(count)"` and increments) so we can assert which window boundaries triggered a regeneration.

**Acceptance**: New unit + integration suites green. Old `OTPTimer` + XCTest tests still green.

### Phase 4 — Generators: `Sendable` annotations + test migration

Modified:
- `Sources/SwiftyOTP/Generators/HashingAlgorithm.swift` — `+ Sendable`.
- `Sources/SwiftyOTP/Generators/Seed.swift` — `+ Sendable`.
- `Sources/SwiftyOTP/Generators/HOTPGenerator.swift` — `+ Sendable`.
- `Sources/SwiftyOTP/Generators/TOTPGenerator.swift` — `+ Sendable`, `currentDateProvider: @Sendable () -> Date`.

Test files migrated in place (no V2 — generators have no behavioral change):
- `Tests/SwiftyOTPTests/HOTPGeneratorTests.swift` → `@Suite final class : LeakTrackingTestCase`.
- `Tests/SwiftyOTPTests/TOTPGeneratorTests.swift` → swift-testing with parameterized `@Test` over RFC 6238 vectors.
- `Tests/SwiftyOTPTests/SeedTests.swift` → swift-testing.

**Acceptance**: Generator tests pass on swift-testing. `Countdown(V2)` and `OTPTimer(V2)` test files unchanged.

### Phase 5 — Cutover

Single commit:

1. **Delete**:
   - `Sources/SwiftyOTP/Timer/Countdown.swift` (old)
   - `Sources/SwiftyOTP/Timer/OTPTimer.swift` (old)
   - `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift` (old)
   - `Tests/SwiftyOTPTests/CountdownTests.swift` (old XCTest)
   - `Tests/SwiftyOTPTests/OTPTimerTests.swift` (old XCTest)
   - `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift` (old XCTest)
   - `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`
   - `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`
   - `Tests/SwiftyOTPTests/Helper/DateProvider.swift`
2. **Rename**:
   - `CountdownV2.swift` → `Countdown.swift`, type `CountdownV2` → `Countdown`.
   - `OTPTimerV2.swift` → `OTPTimer.swift`, type `OTPTimerV2` → `OTPTimer`.
   - `OTPTimerV2+TOTPGenerator.swift` → `OTPTimer+TOTPGenerator.swift`.
   - Test files mirror the renames (`CountdownV2Tests` → `CountdownTests`, etc.).
3. **`Package.swift`**: replace the approachable-concurrency upcoming-feature set with `.enableUpcomingFeature("StrictConcurrency")`. Keep `swiftLanguageModes: [.v6]`.
4. Build + full test run. Fix any concurrency diagnostics that surface (expected: small, closure-isolation specifics).

**Acceptance**:
- `BuildProject` clean with `swiftLanguageModes: [.v6]` + `.enableUpcomingFeature("StrictConcurrency")`.
- `RunAllTests` green.
- `git grep -nE "Combine|Foundation\\.Timer|ObservableObject" -- Sources/` → 0 hits.
- `git grep -n "import XCTest" -- Tests/` → 0 hits.
- `git grep -n "V2" -- Sources/ Tests/` → 0 hits.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `Task { for await tick in countdown.ticks { … } }` inside an `@MainActor` class doesn't inherit MainActor isolation. | Phase 3 acceptance verifies the closure is `@MainActor`. If the compiler doesn't infer it, mark explicitly: `Task { @MainActor [weak self] in … }`. |
| `clock.timer(interval: .seconds(1))` with `TestClock.advance(by:)` semantics differ subtly from `Foundation.Timer` — could miss the first tick or fire an extra at boundaries. | Phase 2 tests assert behavioral parity against the same RFC vectors and window-boundary cases the legacy `CountdownTests.swift` covers. If a discrepancy surfaces, switch the producer to `clock.sleep(for: .seconds(1))` in a manual loop. |
| `Task.megaYield` is heuristic — flaky tests on slower CI runners. | Default `count: 20` per the swift-clocks reference helper; bump per-test if a specific test is flaky. A test that needs `>50` is a smell — investigate before bumping. |
| Strict-concurrency diagnostics balloon at cutover. | Phases 2 & 3 are written *with* strict concurrency in mind even though the package is in approachable mode. Reviewer mentally checks new code against the strict ruleset on every Phase 2/3 commit. Cutover diagnostics should be sparse. |
| `code-keeper-authenticator` breaks on cutover. | Out of scope. Consumer should pin SwiftyOTP to the pre-migration tag until their own update lands. Documented as follow-up. |
| Continuation termination race: in-flight `broadcastTick` snapshots a continuation, releases the lock, then yields — but the continuation could terminate between snapshot and yield. | `AsyncStream.Continuation.yield` is safe to call after termination (returns `.terminated`, no crash). Acceptable. |
| `@unchecked Sendable` on `DateBox` violates CLAUDE.md if anyone copies the pattern into Sources/. | DateBox lives only in `Tests/Helper/`. Doc-comment explicitly forbids copying into Sources/. |

## Out of scope (documented follow-up)

`code-keeper-authenticator/CodeKeeperApp.swift` and `OTPViewModel.swift` will need updates after this migration ships:

- `OTPViewModel` → `@Observable` model that owns an `OTPTimer` directly and exposes derived display state (formatted OTP, countdown string, progress).
- `OTPCodeProvider` protocol likely deletable — its purpose was to abstract the Combine publisher.
- Shared `static let countdown = Countdown(timeStep: 30)` stays.

That work gets its own brainstorming + plan in the consumer repo when this migration ships.

## Acceptance criteria (overall)

The migration is complete when:

1. All five phases are merged.
2. `BuildProject` clean with `swiftLanguageModes: [.v6]` + `.enableUpcomingFeature("StrictConcurrency")`.
3. `RunAllTests` green; every test file uses swift-testing (`@Test`, `#expect`); zero `import XCTest` in `Tests/`.
4. `git grep -nE "Combine|Foundation\\.Timer|ObservableObject" -- Sources/` → 0 hits.
5. The public API matches the shapes declared in **Component shapes**.
6. `Package.swift` declares `.iOS(.v17), .macOS(.v14)`.
7. `CLAUDE.md` is unchanged — the migration *implements* it, doesn't rewrite it.
8. Each phase is its own commit (or PR) following the commit conventions in `CLAUDE.md`.
