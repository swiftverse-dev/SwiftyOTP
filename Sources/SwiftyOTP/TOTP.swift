//
//  TOTP.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

public struct TOTP {
    static var currentDateProvider: () -> Date = Date.init
    
    public let seed: Data
    public let digits: Int
    public let timeStep: UInt64
    public let algorithm: HashingAlgorithm
    
    private enum Error: Swift.Error {
        case digitsNumberOutOfBounds(Int)
        
        var description: String {
            let digits = switch self{
            case .digitsNumberOutOfBounds(let n): n
            }
            return "Expected digits number in (6...8) interval. Got \(digits)"
        }
    }
    
    /// Initializes a Time-Based OTP generator of 6 digits with the provided seed, time step, and hashing algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - timeStep: The time step duration in seconds. The default is 30 seconds.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    public init(seed: Data, timeStep: UInt64 = 30, algorithm: HashingAlgorithm = .sha1) {
        self.seed = seed
        self.digits = 6
        self.timeStep = timeStep
        self.algorithm = algorithm
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
        guard Self.isDigitsNumberValid(digits) else { throw Error.digitsNumberOutOfBounds(digits) }
        self.seed = seed
        self.digits = Int(digits)
        self.timeStep = timeStep
        self.algorithm = algorithm
    }
    
    
    /// The current One-Time Password (OTP) for the current time.
    public var currentOTP: String {
        otp(at: Self.currentDateProvider())
    }

    /// Generate the One-Time Password (OTP) for the provided Date.
    public func otp(at date: Date) -> String {
        let stepCounter = stepCounter(at: date)
        let counterMessage = stepCounter.bigEndian.data
        
        let hmac = algorithm.hmac(for: counterMessage, using: seed)
        
        // Get last 4 bits
        let offset = Int((hmac.last ?? 0x00) & 0x0f)
        let fourBytesAtOffset = hmac.bytes[offset..<offset+4].map{$0}.asUInt32!
        let maskedFourBytes = fourBytesAtOffset & 0x7fffffff
        
        let pow = pow(10, Float(digits)).asUInt32
        let token = maskedFourBytes % pow
        
        var otp = "\(token)"
        if otp.count < digits {
            let padding = (0..<(digits - otp.count)).map{ _ in "0" }.joined()
            otp = padding + otp
        }
        
        return otp
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
    static func isDigitsNumberValid(_ digits: Int) -> Bool { (6...8) ~= digits }
    
    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}


// MARK: HashingAlgorithm - Hmac
private extension HashingAlgorithm {
    func hmac(for data: Data, using secret: Data) -> Data{
        switch self {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        }
    }
}
