//
//  HOTP.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

/// Represents a Hash-Based One-Time Password (HOTP) generator.
public struct HOTP {
    /// The secret seed data used for generating OTPs.
    public let seed: Data
    
    /// The number of digits in the generated OTP.
    public let digits: Int
    
    /// The hashing algorithm used for OTP generation.
    public let algorithm: HashingAlgorithm
    
    /// Initializes an HOTP generator of 6 digits with the provided seed and optional algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    public init(seed: Data, algorithm: HashingAlgorithm = .sha1) {
        self.seed = seed
        self.digits = 6
        self.algorithm = algorithm
    }
    
    /// Initializes an HOTP generator with the provided seed, number of digits, and optional algorithm.
    ///
    /// - Parameters:
    ///   - seed: The secret seed data used for generating OTPs.
    ///   - digits: The number of digits in the generated OTP. Must be within the range (6...8)
    ///   - algorithm: The hashing algorithm to use for OTP generation. The default is SHA-1.
    /// - Throws:
    ///   - `Error.digitsNumberOutOfBounds`: If the `digits` parameter is not within the valid range.
    public init(seed: Data, digits: Int = 6, algorithm: HashingAlgorithm = .sha1) throws {
        try OTPDigitsChecker.check(digits)
        self.seed = seed
        self.digits = digits
        self.algorithm = algorithm
    }
    
    /// Generates an OTP at the specified step counter value.
    ///
    /// - Parameter stepCounter: The step counter value to use for OTP generation.
    /// - Returns: The generated OTP as a string.
    func otp(at stepCounter: UInt64) -> String {
        let message = stepCounter.bigEndian.data
        let hmac = algorithm.hmac(for: message, using: seed)
        
        // Use the last 4 bits as Offset
        let offset = Int((hmac.last ?? 0x00) & 0x0f)
        let maskedFourBytes = extractMaskedFourBytes(from: hmac, at: offset)
        
        let pow = pow(10, Float(digits)).asUInt32
        let token = maskedFourBytes % pow
        
        return generateStringToken(from: token)
    }
    
    private func extractMaskedFourBytes(from hmac: Data, at offset: Int) -> UInt32 {
        let fourBytesAtOffset = hmac.bytes[offset..<offset+4].map { $0 }.asUInt32!
        return fourBytesAtOffset & 0x7fffffff
    }
    
    private func generateStringToken(from token: UInt32) -> String {
        var otp = "\(token)"
        
        if otp.count < digits {
            let padding = (0..<(digits - otp.count)).map { _ in "0" }.joined()
            otp = padding + otp
        }
        
        return otp
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
