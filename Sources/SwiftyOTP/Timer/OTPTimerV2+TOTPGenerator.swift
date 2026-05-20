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
