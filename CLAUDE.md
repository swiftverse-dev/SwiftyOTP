# SwiftyOTP

## Project overview

Pure Swift Package, no UI layer. Implements RFC 4226 (HOTP) and RFC 6238 (TOTP). Public API surface: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPTimer`, `Countdown`, `Tick`, `TOTPProvider`, `UnixTimestamp`. Targets iOS 17+ and macOS 14+ (driven by Observation framework requirements).

This file describes the conventions the project is migrating *toward*. Code on disk that contradicts a rule (XCTest, `Foundation.Timer`) is legacy awaiting migration, not a counter-example.

Combine is fully gone from `Sources/` and `Tests/` — the old `.publisher` API no longer exists.

## Architecture

Three folders under `Sources/SwiftyOTP/`:

- **`Generators/`** — Stateless value types: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPDigitsChecker`.
- **`Timer/`** — `OTPTimer` (`@MainActor @Observable` model), `Countdown`/`Tick` (driven by `swift-clocks`), `TOTPProvider` protocol, `UnixTimestamp`.
- **`Helpers/`** — Internal extensions on `Data`, `UInt`, etc. Not part of the public surface.

## Coding rules

- Swift 6 + strict concurrency. All public types `Sendable`. No `@unchecked Sendable` shortcuts.
- Time source: `swift-clocks` (`ContinuousClock`, `TestClock`). Never `Foundation.Timer` in production code.
- Observability: `OTPTimer` is `@Observable` (Observation framework). Never `ObservableObject`.
- No Combine, anywhere. It has been removed; don't reintroduce it.
- Value types by default. Reference types only when identity or lifecycle matters (`OTPTimer`).
- Throwing inits for input validation: `Seed` decoding, digit bounds (`6...8`).
- Public API gets doc comments (`///` or `/** */`). Internal helpers stay terse.
- Doc comments must name only symbols that exist. Thrown errors in this package are internal types with no public cases — document `- Throws` by condition ("if `digits` falls outside `6...8`"), never by a made-up error-case name.
- `Sources/SwiftyOTP/Helpers/Data+Utils.swift` exposes `public` extensions on `Data`/`[UInt8]` for backwards compatibility only. Don't add more; prefer internal helpers.
- Group helpers in `private extension` of the owning type.

## Testing rules

- swift-testing only. No new XCTest.
- Naming pattern, exactly:

  ```swift
  @Test
  func `<name of property or method tested> - <description of expected behavior>`() {
      let model = makeSUT()
      #expect(model.currentRoute == .productOverview)
  }
  ```

- `makeSUT` factory pattern for system-under-test construction.
- Memory-leak tracking via swift-testing teardown / `Confirmation` (helper shape pending the migration plan).
- Determinism: inject a test clock (`swift-clocks` `TestClock`) and date provider — never read wall time.
- Use RFC 4226 / RFC 6238 vectors for generator correctness.

## Build & tooling (XcodeBuildMCP)

Prefer XcodeBuildMCP tools over raw shell for Apple-platform work. This is a
pure SwiftPM package with no `.xcodeproj`, so the SwiftPM workflow applies —
the simulator/device tools (`build_sim`, `test_sim`, `discover_projs`, …) are
for app targets and don't apply here.

### Build & test
- Use XcodeBuildMCP's SwiftPM tools (`swift_package_build`, `swift_package_test`, `swift_package_clean`) when the SwiftPM workflow is enabled.
- If those tools aren't exposed in the session, fall back to `swift build` / `swift test` in the shell. Don't invent tool names — check what's actually available first.
- `session_show_defaults` before the first build/test call in a session; never assume defaults are configured.

## Commits

- One-line subject, imperative mood, lowercase first word, no trailing period.
- Reference code symbols in backticks: `` `OTPTimer.Event` ``, `` `Countdown.start` ``.
- Describe what the change does (behavior) — not what file changed.
- Body only when the diff doesn't make the "why" obvious; separated by blank line, wrap at 72.
- No Conventional Commits prefixes. No scope tags. No emoji.
- One logical change per commit.

## What not to do

- Don't introduce `Foundation.Timer`, `ObservableObject`, or wall-clock reads in production code.
- Don't add new XCTest files.
- Don't widen `Seed` decoding or digit-bounds validation to non-throwing — input is untrusted.
- Don't add Combine APIs to any type.
- Don't widen the public surface with extensions on stdlib types.
