//
//  OTPAuthURI.swift
//  SwiftyOTP
//
//  Parser and generator for the `otpauth://` Key URI format used by QR codes
//  and provisioning links.
//

import Foundation
import Base32

/// An account in the `otpauth://` Key URI format, as found in provisioning QR codes:
/// `otpauth://totp/Issuer:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Issuer`.
///
/// Parse one with `init(parsing:)`, build one with `init(kind:secret:issuer:accountName:algorithm:digits:)`
/// and render it with `url`.
public struct OTPAuthURI: Sendable, Equatable {
    /// The OTP flavour and its moving factor.
    public enum Kind: Sendable, Equatable {
        /// Time-based (RFC 6238), with the window length in seconds. Always greater than `0` when parsed.
        case totp(period: UInt)
        /// Counter-based (RFC 4226), with the counter value of the next code.
        case hotp(counter: UInt64)
    }

    /// Why a string is not a usable `otpauth://` URI.
    public enum ParseError: Error, Sendable, Equatable {
        /// The string is not a URL with the `otpauth` scheme.
        case notOTPAuthURI
        /// The type (the URI host) is neither `totp` nor `hotp`.
        case unsupportedType(String)
        /// The `secret` parameter is absent or empty.
        case missingSecret
        /// The `secret` parameter is not valid base32.
        case invalidSecret
        /// The `digits` parameter is not 6, 7 or 8.
        case unsupportedDigits(String)
        /// The `algorithm` parameter is not SHA1, SHA256 or SHA512.
        case unsupportedAlgorithm(String)
        /// The `period` parameter is not a whole number of seconds greater than `0`.
        case invalidPeriod(String)
        /// An `hotp` URI has no `counter` parameter.
        case missingCounter
        /// The `counter` parameter is not a non-negative integer.
        case invalidCounter(String)
    }

    /// Whether the account is TOTP or HOTP, with its period or counter.
    public var kind: Kind
    /// The decoded secret.
    public var secret: Data
    /// The service the account belongs to, if the URI names one.
    public var issuer: String?
    /// The account name from the label, usually a username or an email address.
    public var accountName: String
    /// The HMAC hash function.
    public var algorithm: HashingAlgorithm
    /// The number of digits in a code.
    public var digits: Int

    /// Creates a URI from its parts, without validating them.
    ///
    /// `digits` outside `6...8` or a `.totp(period: 0)` kind produce a `url`
    /// that `init(parsing:)` rejects.
    public init(
        kind: Kind,
        secret: Data,
        issuer: String? = nil,
        accountName: String,
        algorithm: HashingAlgorithm = .sha1,
        digits: Int = 6
    ) {
        self.kind = kind
        self.secret = secret
        self.issuer = issuer
        self.accountName = accountName
        self.algorithm = algorithm
        self.digits = digits
    }

    /// Parses an `otpauth://` URI.
    ///
    /// Missing optional parameters take the format's defaults: SHA1, 6 digits,
    /// a 30 second period. The issuer comes from the `issuer` parameter, or
    /// from the label prefix (`Issuer:account`) when the parameter is absent.
    /// The secret is decoded leniently, as `Seed.base32` does.
    ///
    /// - Throws: The `ParseError` naming the first problem found.
    public init(parsing string: String) throws(ParseError) {
        guard let components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth",
              let type = components.host
        else { throw .notOTPAuthURI }

        let query = Self.firstValues(of: components.queryItems ?? [])

        // Split on a literal `:` first, so an issuer with an encoded colon stays whole;
        // fall back to an encoded `%3A` separator, which the format also allows.
        let encodedLabel = components.percentEncodedPath.drop { $0 == "/" }
        let parts = encodedLabel.contains(":")
            ? encodedLabel.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(Self.decode)
            : Self.decode(encodedLabel).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let labelIssuer = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespaces) : nil
        accountName = (parts.last ?? "").trimmingCharacters(in: .whitespaces)
        issuer = [query["issuer"], labelIssuer]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        guard let rawSecret = query["secret"], !rawSecret.isEmpty else { throw .missingSecret }
        guard let secret = try? Seed.base32(rawSecret).data() else { throw .invalidSecret }
        self.secret = secret

        if let raw = query["algorithm"] {
            guard let algorithm = HashingAlgorithm(rawValue: raw.uppercased()) else {
                throw .unsupportedAlgorithm(raw)
            }
            self.algorithm = algorithm
        } else {
            algorithm = .sha1
        }

        if let raw = query["digits"] {
            guard let digits = Int(raw), (6...8).contains(digits) else { throw .unsupportedDigits(raw) }
            self.digits = digits
        } else {
            digits = 6
        }

        switch type.lowercased() {
        case "totp":
            let raw = query["period"] ?? "30"
            guard let period = UInt(raw), period > 0 else { throw .invalidPeriod(raw) }
            kind = .totp(period: period)
        case "hotp":
            guard let raw = query["counter"] else { throw .missingCounter }
            guard let counter = UInt64(raw) else { throw .invalidCounter(raw) }
            kind = .hotp(counter: counter)
        default:
            throw .unsupportedType(type)
        }
    }

    /// The URI in `otpauth://` form, with every parameter written explicitly
    /// and the secret as unpadded uppercase base32.
    public var url: URL {
        var components = URLComponents()
        components.scheme = "otpauth"
        let label = [issuer, accountName]
            .compactMap { $0.map(Self.encode) }
            .joined(separator: ":")
        var items: [(String, String)] = [
            ("secret", secret.base32EncodedString.filter { $0 != "=" }),
        ]
        if let issuer { items.append(("issuer", issuer)) }
        items += [("algorithm", algorithm.rawValue), ("digits", String(digits))]
        switch kind {
        case .totp(let period):
            components.host = "totp"
            items.append(("period", String(period)))
        case .hotp(let counter):
            components.host = "hotp"
            items.append(("counter", String(counter)))
        }
        components.percentEncodedPath = "/" + label
        components.percentEncodedQuery = items
            .map { "\($0)=\(Self.encode($1))" }
            .joined(separator: "&")
        // Every component above is ASCII and percent-encoded, so the URL always exists.
        return components.url!
    }
}

private extension OTPAuthURI {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@")

    static func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    static func decode(_ string: Substring) -> String {
        string.removingPercentEncoding ?? String(string)
    }

    static func firstValues(of items: [URLQueryItem]) -> [String: String] {
        items.reduce(into: [:]) { result, item in
            guard result[item.name.lowercased()] == nil, let value = item.value else { return }
            result[item.name.lowercased()] = value
        }
    }
}
