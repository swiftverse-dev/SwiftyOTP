//
//  TOTPProvider.swift
//
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation
/**
 A protocol for generating Time-Based One-Time Passwords (TOTPs).

 A Time-Based One-Time Password (TOTP) is a short-lived, one-time authentication code that is typically used for two-factor authentication (2FA). TOTPs are generated based on a combination of a secret key and the current time.

 Conforming types to this protocol must implement the method to generate TOTPs for a given time interval since January 1, 1970, as well as provide information about the time step used for generating OTPs.

 Usage:
 - Conform to this protocol to implement TOTP generation logic.
 - Use the conforming type to generate TOTPs as needed.

 Example:
 ```swift
 struct MyTOTPProvider: TOTPProvider {

    func otp(intervalSince1970: TimeInterval) -> OTP {
        // Implement TOTP generation logic here
        // This method should generate and return a TOTP as a string for the given time interval.
        // The OTP should be short-lived and unique for each time interval.
        // Typically, it involves cryptographic operations using a secret key.
        // Return the generated TOTP as a string.
    }
 }
*/
public protocol TOTPProvider {
    /// The type alias for a One-Time Password (OTP), typically represented as a string.
    typealias OTP = String
    
    /**
     Generates a Time-Based One-Time Password (TOTP) for the specified time interval since January 1, 1970.
     
     - Parameter intervalSince1970: The time interval, in seconds, since January 1, 1970, for which to generate the TOTP.
     
     - Returns: A TOTP as a string, unique for the specified time interval.
    */
    func otp(intervalSince1970: TimeInterval) -> OTP
}
