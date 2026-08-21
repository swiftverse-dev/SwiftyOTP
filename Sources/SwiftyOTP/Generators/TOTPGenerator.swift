//
//  TOTPGenerator.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

/// Represents a Time-Based One-Time Password (TOTP) generator.
public struct TOTPGenerator: Sendable {
    var currentDateProvider: @Sendable () -> Date = { Date() }
    
    /// The secret seed data used for generating OTPs.
    public var seed: Data { hotp.seed }
    
    /// The number of digits in the generated OTP, always within `6...8`.
    public var digits: Int { hotp.digits }
    
    /// The hashing algorithm used for OTP generation.
    public var algorithm: HashingAlgorithm { hotp.algorithm }
    
    /// The length of an OTP window in seconds - usually 30 or 60.
    public let timeStep: UInt
    
    private let hotp: HOTPGenerator
    
    /// Initializes a Time-Based OTP generator with the provided seed, number of digits, time step, and hashing algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret, in one of the encodings described by `Seed`.
    ///   - digits: The number of digits in the generated OTP. Must be within the range (6...8).
    ///   - timeStep: The time step duration in seconds. The default is 30 seconds.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    ///
    /// - Throws: An error if `digits` falls outside `6...8`, or if `seed` cannot be
    ///   decoded from its declared encoding (hex, base32 or base64).
    ///
    ///   The concrete error types are internal to the package and carry only a
    ///   human-readable description, so catch them as `Error` rather than by type.
    public init(seed: Seed, digits: Int = 6, timeStep: UInt = 30, algorithm: HashingAlgorithm = .sha1) throws {
        self.hotp = try HOTPGenerator(seed: seed, digits: digits, algorithm: algorithm)
        self.timeStep = timeStep
    }
    
    
    /// The One-Time Password (OTP) for the window containing the current time.
    ///
    /// Reads the generator's date provider, which is `Date()` unless the
    /// package-internal test seam has replaced it.
    public var currentOTP: String {
        otp(at: currentDateProvider())
    }

    /// Generate the One-Time Password (OTP) for the provided Date.
    ///
    /// - Parameter date: Any date inside the window whose OTP is wanted.
    /// - Returns: The OTP, left-padded with zeroes to exactly `digits` characters.
    public func otp(at date: Date) -> String {
        let stepCounter = stepCounter(at: date)
        return hotp.otp(at: stepCounter)
    }
}

// MARK: Helpers
private extension TOTPGenerator {
    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}
