//
//  OTPDigitsChecker.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation
import CryptoKit

enum OTPDigitsChecker {
    
    private enum Error: Swift.Error {
        case digitsNumberOutOfBounds(Int)
        
        var description: String {
            let digits = switch self{
            case .digitsNumberOutOfBounds(let n): n
            }
            return "Expected digits number in (6...8) interval. Got \(digits)"
        }
    }
    
    static func check(_ digits: Int) throws {
        guard (6...8) ~= digits else { throw Error.digitsNumberOutOfBounds(digits)}
    }
}
