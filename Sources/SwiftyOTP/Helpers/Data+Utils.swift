//
//  Data+Utils.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

extension Data {
    var bytes: [UInt8] { Array(self) }
    
    init?(hexString: String) {
            // Remove any spaces or non-hex characters from the input string
            let cleanedHexString = hexString.replacingOccurrences(of: " ", with: "")
            
            // Check if the cleaned hex string has an even number of characters
            guard cleanedHexString.count % 2 == 0 else {
                return nil
            }
            
            var data = Data(capacity: cleanedHexString.count / 2)
            var startIndex = cleanedHexString.startIndex
            
            while startIndex < cleanedHexString.endIndex {
                let endIndex = cleanedHexString.index(startIndex, offsetBy: 2)
                if let byte = UInt8(cleanedHexString[startIndex..<endIndex], radix: 16) {
                    data.append(byte)
                } else {
                    return nil
                }
                startIndex = endIndex
            }
            
            self = data
        }
}

extension Array where Element == UInt8 {
    var asUInt32: UInt32? {
        let byteNumber = 4
        guard count <= byteNumber else { return nil }
        let modulo = count % byteNumber
        let paddingCount = modulo == 0 ? 0 : byteNumber - modulo
        let padding: [UInt8] = (0..<paddingCount).map{ _ in 0 }
        let bytes = padding + self 
        return bytes.withUnsafeBytes{ $0.load(as: UInt32.self) }.bigEndian
    }
}
