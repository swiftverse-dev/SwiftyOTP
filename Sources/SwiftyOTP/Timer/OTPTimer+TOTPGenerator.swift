//
//  OTPTimer+TOTPGenerator.swift
//  SwiftyOTP
//
//  Convenience initialisers wrapping `TOTPGenerator` (or a `Seed`) and
//  constructing a `Countdown` for the consumer.
//

import Foundation

extension TOTPGenerator: TOTPProvider {}

public extension OTPTimer {
    /// Convenience initialiser using an existing `TOTPGenerator`.
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
