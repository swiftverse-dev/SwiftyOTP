//
//  Seed.swift
//  
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import Base32

/// Represents different types of secret seeds used for OTP generation.
public enum Seed: Sendable {
    /// A secret seed provided as a Base64-encoded string.
    case base64(String)
    
    /// A secret seed provided as a Base32-encoded string.
    ///
    /// Decoding is lenient with the way issuers print secrets: spaces, hyphens,
    /// lowercase letters and `=` padding are accepted.
    case base32(String)
    
    /// A secret seed provided as a hexadecimal string.
    case hex(String)
    
    /// A secret seed provided as raw binary data.
    case data(Data)
    
    private struct SeedDecodingError: Error {
        let message: String
        var description: String { message }
    }
    
    func data() throws -> Data {
        switch self {
        case .data(let data):
            return data
            
        case .base32(let base32):
            guard let data = Self.normalizedBase32(base32).base32DecodedData, !data.isEmpty else {
                throw SeedDecodingError(message: "Invalid base32 representation: \(base32)")
            }
            return data
            
        case .base64(let base64):
            guard let data = Data(base64Encoded: base64) else {
                throw SeedDecodingError(message: "Invalid base64 representation: \(base64)")
            }
            return data
            
        case .hex(let hexString):
            guard let data = Data(hexString: hexString) else {
                throw SeedDecodingError(message: "Invalid hex representation: \(hexString)")
            }
            return data
        }
    }

    static func normalizedBase32(_ string: String) -> String {
        let stripped = string.uppercased().filter { !" -=\t\n".contains($0) }
        let padding = (8 - stripped.count % 8) % 8
        return stripped + String(repeating: "=", count: padding)
    }
}
