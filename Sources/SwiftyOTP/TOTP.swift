//
//  TOTP.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

public struct TOTP {
    static var defaultDate: () -> Date = Date.init
    
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
            return "Expected digits number in [6,8] interval. Got \(digits)"
        }
    }
    
    public init(seed: Data, digits: Int = 6, timeStep: UInt64 = 30, algorithm: HashingAlgorithm = .sha1) throws {
        guard Self.isDigitsNumberValid(digits) else { throw Error.digitsNumberOutOfBounds(digits) }
        self.seed = seed
        self.digits = Int(digits)
        self.timeStep = timeStep
        self.algorithm = algorithm
    }
    
    public var currentOTP: String {
        otp(at: Self.defaultDate())
    }
    
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
        
        fileprivate var timestampInSeconds: TimeInterval {
            switch self {
            case let .seconds(timestamp): TimeInterval(timestamp)
            case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
            }
        }
    }
    
    func otp(unixTimestamp timestamp: UnixTimestamp) -> String {
        otp(at: Date(timeIntervalSince1970: timestamp.timestampInSeconds))
    }
}

// Helpers
private extension TOTP {
    
    static func isDigitsNumberValid(_ digits: Int) -> Bool {
        (6...8) ~= digits
    }
    
    func stepCounter(at date: Date) -> UInt64 {
        (date.timeIntervalSince1970.floor / timeStep.asDouble).floor.asUInt
    }
}

private extension HashingAlgorithm {
    func hmac(for data: Data, using secret: Data) -> Data{
        switch self {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        }
    }
}
