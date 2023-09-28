//
//  Seed.swift
//  
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import Base32

/// Represents different types of secret seeds used for OTP generation.
public enum Seed {
    /// A secret seed provided as a Base64-encoded string.
    case base64(String)
    
    /// A secret seed provided as a Base32-encoded string.
    case base32(String)
    
    /// A secret seed provided as a hexadecimal string.
    case hex(String)
    
    /// A secret seed provided as raw binary data.
    case data(Data)
    
    private enum DecodingError: Error {
        case invalidEncoding(message: String)
        case invalidHex(String)
        
        var description: String {
            switch self {
            case let .invalidEncoding(message): message
            case let .invalidHex(hex): "Invalid Hex representation: \(hex)"
            }
        }
    }
    
    func data() throws -> Data {
        switch self {
        case .data(let data):
            return data
            
        case .base32(let base32):
            guard let data = base32.base32DecodedData else {
                throw DecodingError.invalidEncoding(message: "Invalid base32 representation: \(base32)")
            }
            return data
            
        case .base64(let base64):
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.invalidEncoding(message: "Invalid base64 representation: \(base64)")
            }
            return data
            
        case .hex(let hexString):
            return Data(hexString: hexString)
        }
    }
}
