# SwiftyOTP

[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017%2B%20%7C%20macOS%2014%2B-blue.svg)](https://swift.org)

One-time password generation for Swift: RFC 4226 (HOTP) and RFC 6238 (TOTP), plus an `@Observable` timer that keeps a SwiftUI view in sync with the current code and its countdown.

Pure Swift package, no UI layer. Swift 6 strict concurrency, every public type `Sendable`.

## Installation

```swift
.package(url: "https://github.com/swiftverse-dev/SwiftyOTP.git", branch: "main")
```

```swift
.target(name: "MyApp", dependencies: ["SwiftyOTP"])
```

## Quick start

### TOTP

```swift
import SwiftyOTP

let totp = try TOTPGenerator(seed: .base32("JBSWY3DPEHPK3PXP"))
totp.currentOTP            // "492039" — code for now
totp.otp(at: someDate)     // code for an arbitrary date
```

### HOTP

`HOTPGenerator` produces counter-based codes and also backs `TOTPGenerator`.

```swift
let hotp = try HOTPGenerator(seed: .hex("3132333435363738393031323334353637383930"), digits: 8, algorithm: .sha256)
hotp.otp(at: 42)           // code for counter 42
```

### `otpauth://` URIs

```swift
let uri = try OTPAuthURI(parsing: "otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP&issuer=ACME")
uri.issuer                 // "ACME"
uri.kind                   // .totp(period: 30)
let totp = try TOTPGenerator(seed: .data(uri.secret), digits: uri.digits, algorithm: uri.algorithm)
uri.url                    // back to an otpauth:// URL, every parameter explicit
```

Parsing throws an `OTPAuthURI.ParseError` naming the problem: missing or non-base32 secret, digits other than 6/7/8, an algorithm other than SHA1/SHA256/SHA512, a type other than `totp`/`hotp`, a zero period, a missing HOTP counter.

### Live timer in SwiftUI

```swift
struct CodeView: View {
    @State private var timer = try! OTPTimer(seed: .base32("JBSWY3DPEHPK3PXP"))

    var body: some View {
        VStack {
            Text(timer.currentOTP).monospacedDigit()
            ProgressView(value: timer.countdown, total: Double(timer.timeStep))
        }
    }
}
```

`OTPTimer` is `@MainActor @Observable`: read `currentOTP`, `countdown` and `timeStep` directly, no `ObservableObject`, no publishers.

## API

### Generators

| Type | Purpose |
|---|---|
| `Seed` | Secret input: `.base32`, `.base64`, `.hex`, `.data`. Decoding is validated at init and throws on malformed input. Base32 ignores case, spaces, hyphens and `=` padding. |
| `HashingAlgorithm` | `.sha1` (default), `.sha256`, `.sha512`. `Codable` and `CaseIterable`; the raw value is the `otpauth` name (`"SHA1"`, …). |
| `HOTPGenerator` | RFC 4226 counter-based generator. Exposes `seed`, `digits`, `algorithm`, `otp(at:)`. |
| `TOTPGenerator` | RFC 6238 time-based generator over `HOTPGenerator`. Adds `timeStep` (default 30s), `currentOTP`, `otp(at:)`. |

Both generators throw if `digits` falls outside `6...8` or if the seed cannot be decoded; `TOTPGenerator` also throws on a `timeStep` of `0`.

### Provisioning

| Type | Purpose |
|---|---|
| `OTPAuthURI` | Parses (`init(parsing:)`) and generates (`url`) `otpauth://` Key URIs. `kind` is `.totp(period:)` or `.hotp(counter:)`. Throws `OTPAuthURI.ParseError`. |

### Timer

| Type | Purpose |
|---|---|
| `Tick` | One countdown emission: `value` (seconds left in the window), `date`, `windowChanged`. |
| `Countdown` | Lazy multi-subscriber tick source driven by a `Clock<Duration>`. `ticks` returns a fresh `AsyncStream<Tick>`; the producer loop runs only while at least one subscriber iterates. |
| `OTPTimer` | `@MainActor @Observable` driver. `start()` / `stop()` are idempotent; `startsAutomatically: true` by default. |
| `TOTPProvider` | Protocol for OTP generation: `otp(at:)`, with `otp(unixTimestamp:)` and `otp(intervalSince1970:)` provided. `TOTPGenerator` conforms. |
| `UnixTimestamp` | `.seconds` / `.milliseconds` wrapper for timestamp input. |

A new OTP is requested from the provider only when a tick reports a window boundary; intermediate ticks reuse the last value and just move the countdown.

## Testing

Inject a `TestClock` and a deterministic date provider — the library never reads wall time unless you let it:

```swift
let clock = TestClock()
let countdown = Countdown(timeStep: 30, clock: clock, dateProvider: { fixedDate })
let timer = OTPTimer(countdown: countdown, totpProvider: generator)

await clock.advance(by: .seconds(1))
```

Custom providers only need `otp(at:)`:

```swift
struct StubProvider: TOTPProvider {
    func otp(at date: Date) -> TOTP { "123456" }
}
```

## Requirements

iOS 17+ / macOS 14+ (Observation framework), Swift 6.2 toolchain.

Dependencies: [Base32](https://github.com/norio-nomura/Base32), [swift-clocks](https://github.com/pointfreeco/swift-clocks).
