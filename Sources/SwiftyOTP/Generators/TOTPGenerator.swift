//
//  TOTPGenerator.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

/// Represents a Time-Based One-Time Password (HOTP) generator.
public struct TOTPGenerator {
    var currentDateProvider: () -> Date = Date.init
    
    /// The secret seed data used for generating OTPs.
    public var seed: Data { hotp.seed }
    
    /// The number of digits in the generated OTP.
    public var digits: Int { hotp.digits }
    
    /// The hashing algorithm used for OTP generation.
    public var algorithm: HashingAlgorithm { hotp.algorithm }
    
    /// The timestep for computing the OTP - usually 30 or 60 sec
    public let timeStep: UInt
    
    private let hotp: HOTPGenerator
    
    /// Initializes a Time-Based OTP generator with the provided seed, number of digits, time step, and hashing algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - digits: The number of digits in the generated OTP. Must be within the range (6...8).
    ///   - timeStep: The time step duration in seconds. The default is 30 seconds.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    ///
    /// - Throws: `Error.digitsNumberOutOfBounds`: If the `digits` parameter is not within the valid range.
    /// - Throws: `Error.invalidHex`: If the `seed` is not in correct hex representation
    /// - Throws: `Error.invalidEncoding`: If the `seed` is not in correct base32 or base64 representation
    public init(seed: Seed, digits: Int = 6, timeStep: UInt = 30, algorithm: HashingAlgorithm = .sha1) throws {
        self.hotp = try HOTPGenerator(seed: seed, digits: digits, algorithm: algorithm)
        self.timeStep = timeStep
    }
    
    
    /// The current One-Time Password (OTP) for the current time.
    public var currentOTP: String {
        otp(at: currentDateProvider())
    }

    /// Generate the One-Time Password (OTP) for the provided Date.
    public func otp(at date: Date) -> String {
        let stepCounter = stepCounter(at: date)
        return hotp.otp(at: stepCounter)
    }
}

public extension TOTPGenerator {
    enum UnixTimestamp {
        case seconds(UInt64)
        case milliseconds(UInt64)
        
        var timestampInSeconds: TimeInterval {
            switch self {
            case let .seconds(timestamp): TimeInterval(timestamp)
            case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
            }
        }
    }
    
    /// The One-Time Password (OTP) for the provided Unix Timestamp.
    func otp(unixTimestamp timestamp: UnixTimestamp) -> String {
        otp(at: Date(timeIntervalSince1970: timestamp.timestampInSeconds))
    }
    
    /// The One-Time Password (OTP) for the provided TimeInterval
    func otp(intervalSince1970: TimeInterval) -> String {
        otp(at: Date(timeIntervalSince1970: intervalSince1970))
    }
}

// MARK: Helpers
private extension TOTPGenerator {

    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}
