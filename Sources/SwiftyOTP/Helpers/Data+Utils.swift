//
//  Data+Utils.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

extension Data {
    var bytes: [UInt8] { Array(self) }
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
