//
//  TOTPGeneratorTests.swift
//  SwiftyOTPTests
//
//  RFC 6238 reference vectors:
//  https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("TOTPGenerator")
final class TOTPGeneratorTests: LeakTrackingTestCase {

    private var seedSha1: Data {
        "12345678901234567890".data(using: .ascii)!
    }
    private var seedSha256: Data {
        "12345678901234567890123456789012".data(using: .ascii)!
    }
    private var seedSha512: Data {
        "1234567890123456789012345678901234567890123456789012345678901234".data(using: .ascii)!
    }

    private func makeSUT(
        seed: Data,
        timeStep: UInt = 30,
        digits: Int = 8,
        algo: HashingAlgorithm = .sha1
    ) throws -> TOTPGenerator {
        try TOTPGenerator(seed: .data(seed), digits: digits, timeStep: timeStep, algorithm: algo)
    }

    @Test
    func `init - throws when digits is below the valid range`() {
        #expect(throws: (any Error).self) {
            _ = try self.makeSUT(seed: self.seedSha1, digits: 5)
        }
    }

    @Test
    func `init - throws when digits is above the valid range`() {
        #expect(throws: (any Error).self) {
            _ = try self.makeSUT(seed: self.seedSha1, digits: 9)
        }
    }

    @Test
    func `currentOTP - matches RFC 6238 vectors at t=59 across all hashing algorithms`() throws {
        let dateProvider: @Sendable () -> Date = { Date(timeIntervalSince1970: 59) }

        var sutSha1 = try makeSUT(seed: seedSha1, algo: .sha1)
        var sutSha256 = try makeSUT(seed: seedSha256, algo: .sha256)
        var sutSha512 = try makeSUT(seed: seedSha512, algo: .sha512)

        sutSha1.currentDateProvider = dateProvider
        sutSha256.currentDateProvider = dateProvider
        sutSha512.currentDateProvider = dateProvider

        #expect(sutSha1.currentOTP == "94287082")
        #expect(sutSha256.currentOTP == "46119246")
        #expect(sutSha512.currentOTP == "90693936")
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-1 vectors",
        arguments: [
            (UInt64(59),          "94287082"),
            (UInt64(1111111109),  "07081804"),
            (UInt64(1111111111),  "14050471"),
            (UInt64(1234567890),  "89005924"),
            (UInt64(2000000000),  "69279037"),
            (UInt64(20000000000), "65353130"),
        ] as [(UInt64, String)]
    )
    func sha1Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha1, algo: .sha1)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-256 vectors",
        arguments: [
            (UInt64(59),          "46119246"),
            (UInt64(1111111109),  "68084774"),
            (UInt64(1111111111),  "67062674"),
            (UInt64(1234567890),  "91819424"),
            (UInt64(2000000000),  "90698825"),
            (UInt64(20000000000), "77737706"),
        ] as [(UInt64, String)]
    )
    func sha256Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha256, algo: .sha256)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }

    @Test(
        "otp(unixTimestamp:) - matches RFC 6238 SHA-512 vectors",
        arguments: [
            (UInt64(59),          "90693936"),
            (UInt64(1111111109),  "25091201"),
            (UInt64(1111111111),  "99943326"),
            (UInt64(1234567890),  "93441116"),
            (UInt64(2000000000),  "38618901"),
            (UInt64(20000000000), "47863826"),
        ] as [(UInt64, String)]
    )
    func sha512Vector(timestamp: UInt64, expected: String) throws {
        let sut = try makeSUT(seed: seedSha512, algo: .sha512)
        #expect(sut.otp(unixTimestamp: .seconds(timestamp)) == expected)
    }
}
