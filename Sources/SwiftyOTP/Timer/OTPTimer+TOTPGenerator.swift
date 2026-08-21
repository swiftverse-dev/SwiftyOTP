//
//  OTPTimer+TOTPGenerator.swift
//  SwiftyOTP
//
//  Convenience initialisers wrapping `TOTPGenerator` (or a `Seed`) and
//  constructing a `Countdown` for the consumer.
//

import Foundation

/// `TOTPGenerator` is the package's default OTP source for `OTPTimer`.
extension TOTPGenerator: TOTPProvider {}

public extension OTPTimer {
    /// Convenience initialiser using an existing `TOTPGenerator`.
    ///
    /// - Parameters:
    ///   - totpGenerator: The OTP source.
    ///   - timeStep: Window length in seconds for the countdown this creates,
    ///     defaulting to 30. It is *not* checked against
    ///     `totpGenerator.timeStep`; passing a different value makes the
    ///     countdown and the codes drift apart, so keep them in sync.
    ///   - startsAutomatically: See `OTPTimer.init(countdown:totpProvider:startsAutomatically:)`.
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

    /// Convenience initialiser building a `TOTPGenerator` from a `Seed`.
    ///
    /// - Parameters:
    ///   - seed: The secret, in one of the encodings described by `Seed`.
    ///   - digits: Number of digits in the generated OTP. Must be within `6...8`.
    ///   - timeStep: Window length in seconds, used for both the generator and
    ///     the countdown. The default is 30 seconds.
    ///   - algorithm: Hashing algorithm to use. The default is SHA-1.
    ///   - startsAutomatically: See `OTPTimer.init(countdown:totpProvider:startsAutomatically:)`.
    /// - Throws: An error if `digits` falls outside `6...8`, or if `seed` cannot
    ///   be decoded from its declared encoding.
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
