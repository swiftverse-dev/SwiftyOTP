//
//  String+Base32.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Base32
import Foundation

extension String {
    var base32Decoded: Data? {
        base32DecodeToData(self)
    }
    
    var base32DecodedBytes: [UInt8]? {
        base32Decode(self)
    }
}
