//
//  TOTP.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

/// Represents a Time-Based One-Time Password (HOTP) generator.
public struct TOTP {
    static var currentDateProvider: () -> Date = Date.init
    
    /// The secret seed data used for generating OTPs.
    public var seed: Data { hotp.seed }
    
    /// The number of digits in the generated OTP.
    public var digits: Int { hotp.digits }
    
    /// The hashing algorithm used for OTP generation.
    public var algorithm: HashingAlgorithm { hotp.algorithm }
    
    /// The timestep for computing the OTP - usually 30 or 60 sec
    public let timeStep: UInt64
    
    private let hotp: HOTP
    
    /// Initializes a Time-Based OTP generator of 6 digits with the provided seed, time step, and hashing algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - timeStep: The time step duration in seconds. The default is 30 seconds.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    public init(seed: Data, timeStep: UInt64 = 30, algorithm: HashingAlgorithm = .sha1) {
        self.hotp = HOTP(seed: seed, algorithm: algorithm)
        self.timeStep = timeStep
    }

    
    /// Initializes a Time-Based OTP generator with the provided seed, number of digits, time step, and hashing algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - digits: The number of digits in the generated OTP. Must be within the range (6...8).
    ///   - timeStep: The time step duration in seconds. The default is 30 seconds.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    /// - Throws:
    ///   - `Error.digitsNumberOutOfBounds`: If the `digits` parameter is not within the valid range.
    public init(seed: Data, digits: Int, timeStep: UInt64 = 30, algorithm: HashingAlgorithm = .sha1) throws {
        self.hotp = try HOTP(seed: seed, digits: digits, algorithm: algorithm)
        self.timeStep = timeStep
    }
    
    
    /// The current One-Time Password (OTP) for the current time.
    public var currentOTP: String {
        otp(at: Self.currentDateProvider())
    }

    /// Generate the One-Time Password (OTP) for the provided Date.
    public func otp(at date: Date) -> String {
        let stepCounter = stepCounter(at: date)
        return hotp.otp(at: stepCounter)
    }
}

public extension TOTP {
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
}

// MARK: Helpers
private extension TOTP {

    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}
