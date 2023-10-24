//
//  OTPTimer+TOTPGenerator.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation

extension TOTPGenerator: TOTPProvider {}

public extension OTPTimer {
    convenience init(
        totpGenerator: TOTPGenerator,
        interval: Interval = 1.0
    ) throws {
        self.init(startingDate: totpGenerator.currentDateProvider(), interval: interval, otpProvider: totpGenerator)
    }
    
    convenience init(
        seed: Seed,
        digits: Int = 6,
        timeStep: UInt = 30,
        algorithm: HashingAlgorithm = .sha1,
        interval: Interval = 1.0
    ) throws {
        let otpProvider = try TOTPGenerator(seed: seed, digits: digits, timeStep: timeStep, algorithm: algorithm)
        self.init(startingDate: otpProvider.currentDateProvider(), interval: interval, otpProvider: otpProvider)
    }
}
