//
//  TOTP.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

public struct TOTP {
    public let seed: Data
    public let digits: Int
    public let timeStep: UInt64
    public let algorithm: HashingAlgorithm
    
    public init(seed: Data, digits: UInt8 = 6, timeStep: UInt64 = 30, algorithm: HashingAlgorithm = .sha1) {
        self.seed = seed
        self.digits = Int(digits)
        self.timeStep = timeStep
        self.algorithm = algorithm
    }
    
    public func otp(at date: Date) -> String {
        
        let stepNumber = floor(date.timeIntervalSince1970 / timeStep.asDouble).asUInt
        let counterMessage = stepNumber.bigEndian.data
        
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

private extension HashingAlgorithm {
    func hmac(for data: Data, using secret: Data) -> Data{
        switch self {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: secret)))
        }
    }
}
