//
//  HOTP.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

public struct HOTP {
    public let seed: Data
    public let digits: Int
    public let algorithm: HashingAlgorithm
    
    public init(seed: Data, algorithm: HashingAlgorithm = .sha1) {
        self.seed = seed
        self.digits = 6
        self.algorithm = algorithm
    }
    
    public init(seed: Data, digits: Int = 6, algorithm: HashingAlgorithm = .sha1) throws {
        try OTPGenerator.check(digits)
        self.seed = seed
        self.digits = digits
        self.algorithm = algorithm
    }
    
    func otp(at stepCounter: UInt64) -> String {
        OTPGenerator(seed: seed, digits: digits, algorithm: algorithm)
            .otp(at: stepCounter)
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
