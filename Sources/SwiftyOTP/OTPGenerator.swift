//
//  OTPGenerator.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

struct OTPGenerator {
    let seed: Data
    let digits: Int
    let algorithm: HashingAlgorithm
    
    func otp(for stepCounter: UInt64) -> String {
        let message = stepCounter.bigEndian.data
        let hmac = algorithm.hmac(for: message, using: seed)
        
        // Use lasts 4 bits as Offset
        let offset = Int((hmac.last ?? 0x00) & 0x0f)
        let maskedFourBytes = extractMaskedFourBytes(from: hmac, at: offset)
        
        let pow = pow(10, Float(digits)).asUInt32
        let token = maskedFourBytes % pow
        
        return generateStringToken(from: token)
    }
    
    private func extractMaskedFourBytes(from hmac: Data, at offset: Int) -> UInt32 {
        let fourBytesAtOffset = hmac.bytes[offset..<offset+4].map{$0}.asUInt32!
        return fourBytesAtOffset & 0x7fffffff
    }
    
    private func generateStringToken(from token: UInt32) -> String {
        var otp = "\(token)"
        
        if otp.count < digits {
            let padding = (0..<(digits - otp.count)).map{ _ in "0" }.joined()
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
