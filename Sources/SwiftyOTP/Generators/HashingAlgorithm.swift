//
//  HashingAlgorithm.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

/// The HMAC hash function used to derive one-time passwords.
///
/// RFC 4226 mandates SHA-1; RFC 6238 additionally allows SHA-256 and SHA-512.
/// Authenticator apps and provisioning URIs default to `sha1`, so prefer it
/// unless the issuer explicitly specifies another algorithm.
///
/// The raw value is the uppercase name used by the `algorithm` parameter of
/// `otpauth://` URIs, and is what `Codable` encodes.
public enum HashingAlgorithm: String, Sendable, Codable, CaseIterable {
    /// HMAC-SHA1, the RFC 4226 default and the value assumed by most issuers.
    case sha1 = "SHA1"

    /// HMAC-SHA256, as permitted by RFC 6238.
    case sha256 = "SHA256"

    /// HMAC-SHA512, as permitted by RFC 6238.
    case sha512 = "SHA512"
}
