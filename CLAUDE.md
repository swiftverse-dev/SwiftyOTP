# SwiftyOTP

## Project overview

Pure Swift Package, no UI layer. Implements RFC 4226 (HOTP) and RFC 6238 (TOTP). Public API surface: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPTimer`, `Countdown`, `TOTPProvider`. Targets iOS 13+ and macOS 10.15+.

This file describes the conventions the project is migrating *toward*. Code on disk that contradicts a rule (XCTest, Combine `.publisher`, `Foundation.Timer`) is legacy awaiting migration, not a counter-example.

## Architecture

Three folders under `Sources/SwiftyOTP/`:

- **`Generators/`** — Stateless value types: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPDigitsChecker`.
- **`Timer/`** — `OTPTimer` (`@Observable` model), `Countdown` (driven by `swift-clocks`), `TOTPProvider` protocol.
- **`Helpers/`** — Internal extensions on `Data`, `UInt`, etc. Not part of the public surface.

## Coding rules

- Swift 6 + strict concurrency. All public types `Sendable`. No `@unchecked Sendable` shortcuts.
- Time source: `swift-clocks` (`ContinuousClock`, `TestClock`). Never `Foundation.Timer` in production code.
- Observability: `OTPTimer` is `@Observable` (Observation framework). Never `ObservableObject`.
- No Combine in new code. The existing `.publisher` API is legacy, kept until the migration plan removes it.
- Value types by default. Reference types only when identity or lifecycle matters (`OTPTimer`).
- Throwing inits for input validation: `Seed` decoding, digit bounds (`6...8`).
- Public API gets doc comments (`///` or `/** */`). Internal helpers stay terse.
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

## Build & tooling (MCP)

### Build System
- Use `BuildProject` to compile, not shell commands
- SwiftUI previews available via `RenderPreview`

### Testing
- Run tests with `RunAllTests` or `RunSomeTests`
- Test results available via Xcode's test navigator

### Documentation
- Use `DocumentationSearch` to find Apple API docs
- WWDC session transcripts are searchable

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
- Don't add Combine APIs to new types.
