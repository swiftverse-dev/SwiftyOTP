//
//  OTPDigitsChecker.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

enum OTPDigitsChecker {
    
    private struct DigitsNumberOutOfBounds: Swift.Error {
        let digits: Int
        
        init(_ digits: Int) {
            self.digits = digits
        }
        
        var description: String {
            "Expected digits number in (6...8) interval. Got \(digits)"
        }
    }
    
    static func check(_ digits: Int) throws {
        guard (6...8) ~= digits else { throw DigitsNumberOutOfBounds(digits)}
    }
}
