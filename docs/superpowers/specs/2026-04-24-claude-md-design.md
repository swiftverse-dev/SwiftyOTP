# SwiftyOTP `CLAUDE.md` — design spec

Date: 2026-04-24
Status: design (pending implementation plan)

## Goal

Produce a `CLAUDE.md` at the repository root that gives a future Claude session unambiguous, target-state guidance for this project. The file describes the conventions we're migrating *toward*, not the current code on disk. Existing code that does not match (XCTest, Combine `.publisher`, `Foundation.Timer`) is treated as legacy and migrated under separate plans.

The migration plan that drives the codebase from current state to the target documented here is out of scope for this spec and will be brainstormed separately.

## Scope decisions

The following decisions were made during brainstorming and are now fixed for the implementation plan:

1. **Target-only documentation.** `CLAUDE.md` does not describe current code state. When a future session sees code that contradicts the rules (e.g. an `XCTestCase`), it should treat it as legacy awaiting migration, not as a counter-example.
2. **`OTPTimer` is the `@Observable` model.** No other type in the project uses Observation. Actor isolation for `OTPTimer` (`@MainActor` vs. unisolated) is intentionally left out of `CLAUDE.md` and decided in the migration plan.
3. **Combine `.publisher` is legacy.** Not removed by this spec, not used in new code.
4. **Commit strategy: codified existing informal style.** No Conventional Commits.
5. **Verbatim MCP section.** The "Build & tooling (MCP)" section uses the exact wording the user provided.
6. **No commit/PR/agent-etiquette sections beyond what's specified here.** Don't invent rules that weren't asked for.

## File location

`/Users/lorenzo/Dev/Xcode/Side Projects/SwiftyOTP/CLAUDE.md` (repo root).

## Section-by-section content

The implementation plan should produce a single `CLAUDE.md` with the sections below, in this order. Wording within each section may be tightened during implementation, but the substance and rules MUST match what's specified here.

### 1. Project overview

One short paragraph. Must convey:
- Pure Swift Package, no UI layer.
- Implements RFC 4226 (HOTP) and RFC 6238 (TOTP).
- Public API surface: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPTimer`, `Countdown`, `TOTPProvider`.
- Platforms: iOS 13+, macOS 10.15+ (per `Package.swift`).

### 2. Architecture

Describe the three source folders under `Sources/SwiftyOTP/`:
- **`Generators/`** — Stateless value types: `HOTPGenerator`, `TOTPGenerator`, `Seed`, `HashingAlgorithm`, `OTPDigitsChecker`.
- **`Timer/`** — `OTPTimer` (`@Observable` model), `Countdown` (driven by `swift-clocks`), `TOTPProvider` protocol.
- **`Helpers/`** — Internal extensions on `Data`, `UInt`, etc. Not part of the public surface.

### 3. Coding rules (target state)

Bullet list. Each bullet must appear, in this order:
- Swift 6 + strict concurrency. All public types `Sendable`. No `@unchecked Sendable` shortcuts.
- Time source: `swift-clocks` (`ContinuousClock`, `TestClock`). Never `Foundation.Timer` in production code.
- Observability: `OTPTimer` is `@Observable` (Observation framework). Never `ObservableObject`.
- No Combine in new code. Existing `.publisher` API is legacy, kept until the migration plan removes it.
- Value types by default. Reference types only when identity or lifecycle matters (`OTPTimer`).
- Throwing inits for input validation: `Seed` decoding, digit bounds (`6...8`).
- Public API gets doc comments (`///` or `/** */`). Internal helpers stay terse.
- Group helpers in `private extension` of the owning type.

### 4. Testing rules (target state)

Bullet list:
- swift-testing only. No new XCTest.
- Test naming pattern, exactly:
  ```swift
  @Test
  func `<name of property or method tested> - <description of expected behavior>`() {
      let model = makeSUT()
      #expect(model.currentRoute == .productOverview)
  }
  ```
  The example is illustrative; the rule is the backtick-named `<member> - <expected behavior>` format.
- `makeSUT` factory pattern for system-under-test construction.
- Memory-leak tracking via swift-testing teardown / `Confirmation` (concrete helper to be defined in the migration plan, not this spec).
- Determinism: inject a test clock (`swift-clocks` `TestClock`) and date provider — never read wall time.
- Use RFC 4226 / RFC 6238 vectors for generator correctness.

### 5. Build & tooling (MCP)

Verbatim from the user's brief:

```
## Build System
- Use `BuildProject` to compile, not shell commands
- SwiftUI previews available via `RenderPreview`

## Testing
- Run tests with `RunAllTests` or `RunSomeTests`
- Test results available via Xcode's test navigator

## Documentation
- Use `DocumentationSearch` to find Apple API docs
- WWDC session transcripts are searchable
```

These three subsections live under a single `## Build & tooling (MCP)` heading in `CLAUDE.md`. The `RenderPreview` line is preserved verbatim even though there are no SwiftUI previews in the library today.

### 6. Commits

Bullet list, exactly:
- One-line subject, imperative mood, lowercase first word, no trailing period.
- Reference code symbols in backticks: `` `OTPTimer.Event` ``, `` `Countdown.start` ``.
- Describe what the change does (behavior) — not what file changed.
- Body only when the diff doesn't make the "why" obvious; separated by blank line, wrap at 72.
- No Conventional Commits prefixes. No scope tags. No emoji.
- One logical change per commit.

### 7. What not to do

Bullet list:
- Don't introduce `Foundation.Timer`, `ObservableObject`, or wall-clock reads in production code.
- Don't add new XCTest files.
- Don't widen `Seed` decoding or digit-bounds validation to non-throwing — input is untrusted.
- Don't add Combine APIs to new types.

## Out of scope

- Implementing any of the migrations (XCTest → swift-testing, `OTPTimer` → `@Observable`, `Foundation.Timer` → `swift-clocks`, Sendable hardening). Those are separate plans.
- Choosing `OTPTimer`'s actor isolation.
- Removing the legacy `.publisher` API.
- Adding `RenderPreview`-targeted SwiftUI previews.
- Adding agent-etiquette, PR-template, or release-process sections.

## Acceptance criteria

The implementation is complete when:
1. `CLAUDE.md` exists at repo root with the seven sections above, in order, with the content specified.
2. Section 5 contains the user's MCP wording verbatim.
3. Section 6 contains the commit rules verbatim as listed above.
4. The file contains no rule contradicting another rule.
5. The file is committed under the commit conventions defined in section 6.
