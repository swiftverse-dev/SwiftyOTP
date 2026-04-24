# SwiftyOTP — Swift 6 / Observation / swift-clocks migration

Date: 2026-04-24
Status: design (pending implementation plan)
Related: `docs/superpowers/specs/2026-04-24-claude-md-design.md` (target conventions)

## Goal

Migrate `SwiftyOTP` from its current state (Combine + `Foundation.Timer` + XCTest, Swift 6 mode declared but with Sendable hazards) to the target documented in `CLAUDE.md`:
- Strict Swift 6 concurrency, fully Sendable-clean.
- `OTPTimer` as `@Observable`, `@MainActor`-isolated.
- Clock driven by `swift-clocks` (`ContinuousClock` in production, `TestClock` in tests).
- `Countdown` as a non-isolated `Sendable` `final class`, broadcasting via `AsyncStream<Tick>`.
- All tests on swift-testing.
- Combine `.publisher` API removed (clean break, no deprecation window).

The migration is a **major version, breaking change** for consumers — platform minimums bump to **iOS 17 / macOS 14** (driven by `@Observable`).

## Scope decisions

The following decisions were made during brainstorming and are now fixed:

1. **Platform minimums bump to iOS 17 / macOS 14.** Forced by Observation framework. Bundle into the same major-version release as the API redesign.
2. **`OTPTimer` is `@MainActor @Observable final class`.** SwiftUI is the dominant consumer (e.g. `code-keeper-authenticator`); main-actor isolation matches that and avoids actor-hop contortions on the read path. Headless consumers use `MainActor.run`.
3. **`OTPTimer` public API**: two observable properties + `start()`/`stop()` + `timeStep`. `Event` struct deleted. `.publisher` deleted (no deprecation window).
   ```swift
   @MainActor @Observable
   public final class OTPTimer {
       public let timeStep: UInt
       public private(set) var currentOTP: String
       public private(set) var countdown: TimeInterval
       public init(countdown: Countdown, totpProvider: TOTPProvider, startsAutomatically: Bool = true)
       public func start()
       public func stop()
   }
   ```
4. **`Countdown` stays public** — load-bearing per the consumer evidence in `code-keeper-authenticator/CodeKeeperApp.swift:17,50` (one shared `Countdown` synchronizes ticking across all displayed OTP rows).
5. **`Countdown` is `final class`, `Sendable`, non-isolated.** Internal state behind `OSAllocatedUnfairLock<State>` (`import os`) — chosen over `Synchronization.Mutex` because the latter requires iOS 18+/macOS 15+, and we're floored at iOS 17/macOS 14. No public `start()`/`stop()` — the producer task is started lazily on first subscriber, cancelled when the last subscriber drops.
6. **`Countdown` API**:
   ```swift
   public final class Countdown: Sendable {
       public let timeStep: UInt
       public init(timeStep: UInt, clock: some Clock<Duration> = ContinuousClock())
       public var ticks: AsyncStream<Tick> { get }
   }
   public struct Tick: Sendable, Equatable {
       public let value: TimeInterval
       public let date: Date
       public let windowChanged: Bool
   }
   ```
7. **`OTPTimer` consumes `Countdown.ticks` via a single `Task { for await tick in countdown.ticks { ... } }`** owned by `start()` and cancelled by `stop()`/`deinit`. Updates `currentOTP`/`countdown` on `@MainActor` (it is already isolated).
8. **Generators (`HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPDigitsChecker`) get `Sendable` conformance only.** No structural changes. Their public API stays as-is.
9. **`Combine` import is removed entirely from the package.**
10. **`OTPTimer+TOTPGenerator.swift` convenience inits are preserved** — they construct a `Countdown` + `TOTPGenerator` for the consumer. Signature updated to match the new `OTPTimer` init.
11. **Tests migrate to swift-testing.** Existing XCTest helpers are deleted at cutover.
12. **Test memory-leak tracking pattern**: `final class LeakTracker` returned from a `trackForMemoryLeaks(_:)` free function. Holds a `weak var` to the tracked instance and calls `Issue.record(...)` from `deinit` when the weak ref is non-nil. Local-binding lifetime in the test function gives correct teardown timing.
13. **Async event collection pattern**: `collect(_:from:)` free function pulling N values from an `AsyncStream`, used in conjunction with `TestClock.advance(by:)`.
14. **Migration strategy is side-by-side V2 with concurrency relaxation** (see Phasing).
15. **Cutover renames `*V2` → final names in a single commit** at the end of the migration. Strict concurrency is re-enabled in the same commit.
16. **`code-keeper-authenticator` consumer update is out of scope** for this spec but listed as a documented follow-up.
17. **No deprecation period** for the old API. Pre-cutover, both APIs coexist (V2 is additive). Post-cutover, the old API is gone.

## Phasing

Each phase is a self-contained PR. The test suite stays green throughout.

### Phase 0 — Relax concurrency settings

**Files**: `Package.swift`.

- Replace `.enableUpcomingFeature("StrictConcurrency")` in both targets with the **approachable concurrency** upcoming-feature set:
  - `InferIsolatedConformances`
  - `NonisolatedNonsendingByDefault`
  - `DisableOutwardActorInference`
  - `GlobalActorIsolatedTypesUsability`
- If `swiftLanguageMode: .v6` blocks half-migrated code from compiling, downgrade to `.v5` temporarily. Document the intent inline so it isn't lost.
- Bump `platforms` to `.iOS(.v17), .macOS(.v14)`.
- Verify the existing test suite still passes against the relaxed settings.

**Acceptance**: `swift build && swift test` (or `BuildProject` + `RunAllTests` via MCP) succeeds with no behavioural changes.

### Phase 1 — `CountdownV2`

**New files**:
- `Sources/SwiftyOTP/Timer/CountdownV2.swift` — implementation.
- `Tests/SwiftyOTPTests/CountdownV2Tests.swift` — swift-testing suite.
- `Tests/SwiftyOTPTests/Helper/LeakTracker.swift` — `final class LeakTracker` + `trackForMemoryLeaks(_:)`.
- `Tests/SwiftyOTPTests/Helper/AsyncStream+Collect.swift` — `collect(_:from:)` helper.

**Implementation requirements**:
- `final class CountdownV2: Sendable`.
- `OSAllocatedUnfairLock<State>` (`import os`) holding: subscriber continuations keyed by UUID, the running `Task<Void, Never>?` (nil when no subscribers), and `lastWindow: UInt?` for window-change detection. (Not `Synchronization.Mutex` — that needs iOS 18/macOS 15.)
- `init(timeStep:clock:)` stores `timeStep` and a type-erased reference to the clock (or generic + concrete storage trick — implementer's call). Default clock = `ContinuousClock()`.
- `var ticks: AsyncStream<Tick>` — each call returns a fresh stream:
  - In `AsyncStream` builder: register the continuation under a new UUID via `state.withLock`. If subscriber count was zero, spawn the producer task.
  - `continuation.onTermination = { [weak self] _ in self?.unregister(id) }` — under lock: remove continuation; if subscriber count drops to zero, cancel and clear the producer task.
- Producer task body: `for await _ in clock.timer(interval: .seconds(1)) { broadcastTick() }`. `broadcastTick`:
  - Read clock-derived `Date` (use `Date()` is acceptable here since the test path uses `TestClock` and asserts deterministic *intervals*, but prefer carrying a date provider injected through init for explicit testability — see test plan).
  - Compute `currentWindow = UInt(timestamp) / timeStep`, `value = windowSize - timestamp.truncatingRemainder(dividingBy: windowSize)`.
  - `windowChanged = lastWindow == nil || currentWindow > lastWindow`. Update `lastWindow`.
  - Build `Tick(value: value, date: now, windowChanged: windowChanged)`.
  - Yield to every continuation under lock.

**Test requirements (`CountdownV2Tests.swift`)**:
- Naming follows the CLAUDE.md pattern: `` @Test func `<member> - <expected behavior>`() `` with backticks.
- Suite uses a `@Suite struct CountdownV2Tests` (no shared mutable state).
- Each test uses `makeSUT(...)` → `(sut: CountdownV2, leak: LeakTracker, clock: TestClock)`.
- Coverage parity with current `CountdownTests.swift`:
  - `ticks - emits no values until first subscriber awaits`
  - `ticks - emits aligned countdown values with one-second cadence`
  - `ticks - reports windowChanged on first emission`
  - `ticks - reports windowChanged when crossing a window boundary`
  - `ticks - resumes correctly after all subscribers drop and a new one subscribes`
  - `ticks - multiple subscribers receive the same tick stream`
- `TestClock.advance(by: .seconds(N))` drives time forward; `collect(N, from: stream)` pulls N values.
- Memory leak: `let leak = trackForMemoryLeaks(sut)` — implicit teardown on test scope exit.

**Acceptance**: New tests green. Existing XCTest suite still green. Old `Countdown` untouched.

### Phase 2 — `OTPTimerV2`

**New files**:
- `Sources/SwiftyOTP/Timer/OTPTimerV2.swift` — implementation.
- `Sources/SwiftyOTP/Timer/OTPTimerV2+TOTPGenerator.swift` — convenience inits.
- `Tests/SwiftyOTPTests/OTPTimerV2Tests.swift` — unit suite.
- `Tests/SwiftyOTPTests/OTPTimerV2IntegrationTests.swift` — integration with `TOTPGenerator`.

**Implementation requirements**:
- `@MainActor @Observable public final class OTPTimerV2`.
- Stored properties: `let timeStep: UInt`, `private(set) var currentOTP: String = ""`, `private(set) var countdown: TimeInterval = 0`.
- Private: `let countdown: CountdownV2`, `let totpProvider: TOTPProvider`, `var consumerTask: Task<Void, Never>?`, `var lastOTP: String?`.
- `init(countdown:totpProvider:startsAutomatically: Bool = true)`:
  - Stores dependencies.
  - If `startsAutomatically`, calls `start()`.
- `start()`: idempotent. If `consumerTask != nil`, return. Otherwise:
  ```swift
  consumerTask = Task { [weak self, totpProvider] in
      guard let stream = self?.countdown.ticks else { return }
      for await tick in stream {
          guard let self else { return }
          let otp = (tick.windowChanged || self.lastOTP == nil)
              ? totpProvider.otp(intervalSince1970: tick.date.timeIntervalSince1970)
              : self.lastOTP!
          self.lastOTP = otp
          self.currentOTP = otp
          self.countdown = tick.value
      }
  }
  ```
  Note: `self.currentOTP = ...` is on `@MainActor` because the enclosing closure inherits it via the `@MainActor` class isolation; the `Task` body is `@MainActor`-isolated by inheritance. Confirm with the compiler; if not inherited, mark the closure `@MainActor`.
- `stop()`: `consumerTask?.cancel(); consumerTask = nil`.
- `deinit` requires care on `@MainActor` types. Use the modern pattern: `consumerTask?.cancel()` from `deinit` is permitted (cancel is nonisolated). No need to nil out properties.

**`OTPTimerV2+TOTPGenerator.swift`**:
- Two convenience inits matching the existing file's shape:
  ```swift
  public extension OTPTimerV2 {
      convenience init(totpGenerator: TOTPGenerator, timeStep: UInt = 30, startsAutomatically: Bool = true)
      convenience init(seed: Seed, digits: Int = 6, timeStep: UInt = 30,
                       algorithm: HashingAlgorithm = .sha1, startsAutomatically: Bool = true) throws
  }
  ```
- The `interval` parameter is dropped — `Countdown` always ticks at 1 Hz now.

**Test requirements**:
- `OTPTimerV2Tests.swift` — uses an `OTPProviderSpy` (port of the existing one) and a `TestClock`-backed `CountdownV2`. Verifies:
  - `currentOTP - is empty before first tick`
  - `currentOTP - updates from provider on first tick`
  - `currentOTP - changes only on window boundary`
  - `countdown - mirrors the latest tick value`
  - `start - is idempotent when called twice`
  - `stop - stops updating observable state`
  - `stop - cancels the consumer task`
- `OTPTimerV2IntegrationTests.swift` — uses real `TOTPGenerator` with the RFC seed (`"12345678901234567890"`). Asserts the same OTP values the current integration test asserts (`84755224`, `94287082`).
- Observation surface: tests read `sut.currentOTP` / `sut.countdown` directly and assert. They do NOT use `withObservationTracking` (overkill for these assertions).
- `@MainActor` on the suite (`@MainActor @Suite struct OTPTimerV2Tests`) so test methods can touch `OTPTimerV2` synchronously.

**Acceptance**: New unit + integration suites green. Existing tests still green.

### Phase 3 — Generators: in-place Sendable annotations + test migration

**Files modified**:
- `Sources/SwiftyOTP/Generators/HOTPGenerator.swift` — add `Sendable` to the struct.
- `Sources/SwiftyOTP/Generators/TOTPGenerator.swift` — add `Sendable`. The `currentDateProvider: () -> Date` stored property must become `@Sendable () -> Date` (or be replaced with a `some Clock<Duration>` + `Date` derivation — implementer's call; default to keeping the closure but marking `@Sendable`).
- `Sources/SwiftyOTP/Generators/Seed.swift` — `enum Seed: Sendable` (it already conforms implicitly because all cases hold `Sendable` payloads, but make it explicit for the API contract).
- `Sources/SwiftyOTP/Generators/HashingAlgorithm.swift` — add `Sendable`.
- `Sources/SwiftyOTP/Generators/OTPDigitsChecker.swift` — internal, no change needed.
- `Sources/SwiftyOTP/Helpers/*.swift` — add `Sendable` to anything publicly exposed; otherwise leave alone.

**Tests migrated in place** (no V2):
- `Tests/SwiftyOTPTests/HOTPGeneratorTests.swift` → swift-testing.
- `Tests/SwiftyOTPTests/TOTPGeneratorTests.swift` → swift-testing.
- `Tests/SwiftyOTPTests/SeedTests.swift` → swift-testing.

The XCTest versions are deleted in this phase since the generators don't have a "V2" variant — there's nothing to switch between.

**Acceptance**: Generator tests pass on swift-testing. `Countdown(V2)` and `OTPTimer(V2)` test files unchanged.

### Phase 4 — Cutover

**Single commit**:
1. Delete:
   - `Sources/SwiftyOTP/Timer/Countdown.swift` (old).
   - `Sources/SwiftyOTP/Timer/OTPTimer.swift` (old).
   - `Sources/SwiftyOTP/Timer/OTPTimer+TOTPGenerator.swift` (old).
   - `Tests/SwiftyOTPTests/CountdownTests.swift` (old XCTest).
   - `Tests/SwiftyOTPTests/OTPTimerTests.swift` (old XCTest).
   - `Tests/SwiftyOTPTests/OTPTimerIntegrationTests.swift` (old XCTest).
   - `Tests/SwiftyOTPTests/Helper/OTPTimerTestCase.swift`.
   - `Tests/SwiftyOTPTests/Helper/XCTestCase+MemoryLeakTracking.swift`.
   - `Tests/SwiftyOTPTests/Helper/DateProvider.swift`.
2. Rename:
   - `CountdownV2.swift` → `Countdown.swift`. Type `CountdownV2` → `Countdown`.
   - `OTPTimerV2.swift` → `OTPTimer.swift`. Type `OTPTimerV2` → `OTPTimer`.
   - `OTPTimerV2+TOTPGenerator.swift` → `OTPTimer+TOTPGenerator.swift`.
   - Test files mirror the renames.
3. `Package.swift`:
   - Replace the approachable-concurrency upcoming-feature set with `.enableUpcomingFeature("StrictConcurrency")`.
   - Restore `swiftLanguageMode: .v6` if it was downgraded.
4. Run full build + test. Fix any concurrency diagnostics that surface (expected: minimal — mostly closure-isolation specifics).
5. Verify the public API matches what's declared in scope decisions 3, 5, 6.

**Acceptance**: `BuildProject` clean. `RunAllTests` green. No `Combine` import anywhere in the package. No XCTest anywhere in the package. `git grep -E "Foundation\.Timer|ObservableObject|Combine"` returns zero hits in `Sources/`.

### Phase 5 — Consumer follow-up (out of scope, tracked here)

`code-keeper-authenticator/CodeKeeperApp.swift` and `OTPViewModel.swift` need updates:
- `OTPViewModel` → `@Observable` model that owns an `OTPTimer` and exposes derived display state (`currentOTP` formatted with spaces, `countDown` string, `progress`).
- `OTPCodeProvider` protocol → likely deleted (its purpose was to abstract the Combine publisher; with `@Observable` `OTPTimer` directly observable, the indirection is unnecessary).
- App-level `static let countdown = Countdown(timeStep: 30)` stays as-is.

This phase is **not** part of this migration plan. It will be brainstormed and planned separately when the SwiftyOTP migration ships.

## Out of scope

- Updating `code-keeper-authenticator` (Phase 5 above).
- Adding new features (e.g. URI parsing, keychain helpers, additional algorithms).
- Performance work beyond what naturally falls out of the rewrite.
- Documentation site / DocC tooling beyond inline doc comments.
- A deprecation window for the old `.publisher` API.
- CI configuration changes.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Strict concurrency diagnostics in cutover commit balloon. | Phase 0 keeps approachable concurrency throughout 1–3, so V2 code is written with concurrency in mind from day one. Cutover-only diagnostics should be small. |
| `@Observable` + `@MainActor` + actor-hop in `Task { for await ... }` has subtle isolation issues. | Phase 2 acceptance includes explicit verification; if the closure doesn't inherit `@MainActor`, mark it so. Both patterns are documented in Apple's swift-evolution docs. |
| (Resolved in scope decision 5 — `OSAllocatedUnfairLock` chosen instead of `Mutex` to fit the iOS 17 floor.) | n/a |
| `TestClock.advance(by:)` with `clock.timer(interval:)` semantics differ subtly from `Foundation.Timer`. | Phase 1 tests assert behavioral parity with the existing `CountdownTests.swift` cases; if a discrepancy surfaces, adjust the producer loop (e.g. use `clock.sleep` + manual loop instead of `clock.timer`). |
| `code-keeper-authenticator` breaks on cutover before Phase 5 lands. | Phase 5 is explicitly called out. Consumer's branch should pin SwiftyOTP to the pre-migration tag until updated. |

## Acceptance criteria (overall)

The migration is complete when:

1. All five phases listed under Phasing are merged.
2. `BuildProject` produces a clean build with `swiftLanguageMode: .v6` and `.enableUpcomingFeature("StrictConcurrency")` in `Package.swift`.
3. `RunAllTests` green; every test file uses swift-testing (`@Test`, `#expect`); zero `import XCTest` in `Tests/`.
4. `git grep -nE "Combine|Foundation\\.Timer|ObservableObject" -- Sources/` returns no hits.
5. The public API matches the shapes declared in scope decisions 3, 5, 6.
6. `Package.swift` declares `.iOS(.v17), .macOS(.v14)`.
7. CLAUDE.md (per `2026-04-24-claude-md-design.md`) is unchanged — the migration *implements* it, doesn't rewrite it.
8. Each phase is its own commit (or PR) following the commit conventions in `CLAUDE.md`.
