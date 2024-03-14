//
//  OTPTimer+TOTPGenerator.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation

extension TOTPGenerator: TOTPProvider {}

public extension OTPTimer {
    /**
    Convenience initializer for OTPTimer with a custom TOTP generator.

    - Parameters:
     - totpGenerator: An instance of TOTPGenerator for custom TOTP generation.
     - interval: The time interval (in seconds) at which events are generated (default is 1.0).
     - timeStep: The time step duration (in seconds) for TOTP generation (default is 30).
     - startsAutomatically: A flag that will make countdown starts automatically after init
    
    - Throws: An error if there are any issues during the initialization process.
    */
    convenience init(
        totpGenerator: TOTPGenerator,
        interval: Interval = 1.0,
        timeStep: UInt = 30,
        startsAutomatically: Bool = true
    ) throws {
        self.init(
            countdown: Countdown(timeStep: timeStep, interval: interval),
            totpProvider: totpGenerator,
            startsAutomatically: startsAutomatically
        )
    }
    
    /**
    Convenience initializer for `OTPTimer` with `TOTPGenerator` as default otp provider

    - Parameters:
       - seed: A secret key seed for TOTP generation.
       - digits: The number of digits in the generated OTP (default is 6).
       - timeStep: The time step duration (in seconds) for TOTP generation (default is 30).
       - algorithm: The hashing algorithm to use for TOTP generation (default is SHA-1).
       - interval: The time interval (in seconds) at which events are generated (default is 1.0).
       - startsAutomatically: A flag that will make countdown starts automatically after init

    - Throws: An error if there are any issues during the initialization process.
     */
    convenience init(
        seed: Seed,
        digits: Int = 6,
        timeStep: UInt = 30,
        algorithm: HashingAlgorithm = .sha1,
        interval: Interval = 1.0,
        startsAutomatically: Bool = true
    ) throws {
        let otpProvider = try TOTPGenerator(seed: seed, digits: digits, timeStep: timeStep, algorithm: algorithm)
        self.init(
            countdown: Countdown(timeStep: timeStep, interval: interval),
            totpProvider: otpProvider,
            startsAutomatically: startsAutomatically
        )
    }
}
