//
//  TOTPProvider.swift
//
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation

public protocol TOTPProvider {
    typealias OTP = String
    var timeStep: UInt { get }
    func otp(intervalSince1970: TimeInterval) -> OTP
}


extension TOTPGenerator: TOTPProvider {}
