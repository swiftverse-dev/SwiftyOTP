//
//  OTPAuthURITests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import SwiftyOTP

@Suite("OTPAuthURI")
struct OTPAuthURITests {

    private func parse(_ string: String) throws(OTPAuthURI.ParseError) -> OTPAuthURI {
        try OTPAuthURI(parsing: string)
    }

    @Test
    func `init(parsing:) - reads a full TOTP URI`() throws {
        let sut = try parse("otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60")

        #expect(sut.kind == .totp(period: 60))
        #expect(sut.issuer == "ACME Co")
        #expect(sut.accountName == "john.doe@email.com")
        #expect(sut.algorithm == .sha256)
        #expect(sut.digits == 8)
        #expect(sut.secret == (try HOTPGenerator(seed: .base32("HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ")).seed))
    }

    @Test
    func `init(parsing:) - applies defaults when optional parameters are absent`() throws {
        let sut = try parse("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP")

        #expect(sut.kind == .totp(period: 30))
        #expect(sut.issuer == nil)
        #expect(sut.accountName == "alice")
        #expect(sut.algorithm == .sha1)
        #expect(sut.digits == 6)
    }

    @Test
    func `init(parsing:) - takes the issuer from the label prefix when the parameter is absent`() throws {
        let sut = try parse("otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP")
        #expect(sut.issuer == "Example")
        #expect(sut.accountName == "alice@google.com")
    }

    @Test
    func `init(parsing:) - prefers the issuer parameter over the label prefix`() throws {
        let sut = try parse("otpauth://totp/Old:alice?secret=JBSWY3DPEHPK3PXP&issuer=New")
        #expect(sut.issuer == "New")
    }

    @Test
    func `init(parsing:) - accepts an encoded separator, case-insensitive scheme, type and algorithm`() throws {
        let sut = try parse("OTPAUTH://TOTP/Example%3Aalice?secret=jbswy3dpehpk3pxp&algorithm=sha512")
        #expect(sut.issuer == "Example")
        #expect(sut.accountName == "alice")
        #expect(sut.algorithm == .sha512)
    }

    @Test
    func `init(parsing:) - reads an HOTP URI with its counter`() throws {
        let sut = try parse("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=42")
        #expect(sut.kind == .hotp(counter: 42))
    }

    @Test(arguments: [
        ("https://example.com", OTPAuthURI.ParseError.notOTPAuthURI),
        ("not a uri", .notOTPAuthURI),
        ("otpauth://motp/alice?secret=JBSWY3DPEHPK3PXP", .unsupportedType("motp")),
        ("otpauth://totp/alice", .missingSecret),
        ("otpauth://totp/alice?secret=", .missingSecret),
        ("otpauth://totp/alice?secret=JBSW1!", .invalidSecret),
        ("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=5", .unsupportedDigits("5")),
        ("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=six", .unsupportedDigits("six")),
        ("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&algorithm=MD5", .unsupportedAlgorithm("MD5")),
        ("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0", .invalidPeriod("0")),
        ("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=-30", .invalidPeriod("-30")),
        ("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP", .missingCounter),
        ("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=x", .invalidCounter("x")),
    ])
    func `init(parsing:) - throws the precise error`(uri: String, expected: OTPAuthURI.ParseError) {
        #expect(throws: expected) { try self.parse(uri) }
    }

    @Test(arguments: [
        OTPAuthURI(kind: .totp(period: 30), secret: Data("Hello!".utf8), issuer: "ACME & Co: Ltd", accountName: "john+doe@email.com"),
        OTPAuthURI(kind: .totp(period: 60), secret: Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01]), accountName: "Ünïcode user", algorithm: .sha512, digits: 8),
        OTPAuthURI(kind: .hotp(counter: 7), secret: Data("12345678901234567890".utf8), issuer: "Bank", accountName: "alice", algorithm: .sha256, digits: 7),
    ])
    func `url - parses back to the same value`(sut: OTPAuthURI) throws {
        #expect(try parse(sut.url.absoluteString) == sut)
    }

    @Test
    func `url - writes every parameter with an unpadded secret`() {
        let sut = OTPAuthURI(kind: .totp(period: 30), secret: Data("foo".utf8), issuer: "ACME Co", accountName: "alice")
        #expect(sut.url.absoluteString == "otpauth://totp/ACME%20Co:alice?secret=MZXW6&issuer=ACME%20Co&algorithm=SHA1&digits=6&period=30")
    }
}
