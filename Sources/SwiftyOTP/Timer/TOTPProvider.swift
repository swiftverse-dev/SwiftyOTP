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

 Conforming types implement a single requirement: producing the OTP for a given `Date`. The timestamp-based overloads are provided by the protocol extension.

 `TOTPGenerator` already conforms; conform your own type when you need a custom or stubbed OTP source, for example to drive `OTPTimer` in tests.

 Example:
 ```swift
 struct MyTOTPProvider: TOTPProvider {
     func otp(at date: Date) -> TOTP {
         // Derive the window from `date` and return the code for it,
         // typically an HMAC over the window index using a secret key.
         "123456"
     }
 }
 ```
*/
public protocol TOTPProvider: Sendable {
    /// The type alias for a One-Time Password (OTP), typically represented as a string.
    typealias TOTP = String

    /**
     Generates a Time-Based One-Time Password (TOTP) for the specified ``Date``.

     - Parameter date: The ``Date`` from which the TOTP is generated.

     - Returns: A TOTP as a string, unique for the specified time interval.
    */
    func otp(at date: Date) -> TOTP
}

public extension TOTPProvider {
    /// The One-Time Password (OTP) for the provided Unix timestamp.
    ///
    /// - Parameter timestamp: A `UnixTimestamp` in seconds or milliseconds.
    /// - Returns: The OTP for the window containing that instant.
    func otp(unixTimestamp timestamp: UnixTimestamp) -> TOTP {
        otp(at: Date(timeIntervalSince1970: timestamp.timestampInSeconds))
    }

    /// The One-Time Password (OTP) for the provided time interval.
    ///
    /// - Parameter intervalSince1970: Seconds since the Unix epoch.
    /// - Returns: The OTP for the window containing that instant.
    func otp(intervalSince1970: TimeInterval) -> TOTP {
        otp(at: Date(timeIntervalSince1970: intervalSince1970))
    }
}
