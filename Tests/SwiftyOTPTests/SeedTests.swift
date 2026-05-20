//
//  SeedTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("Seed")
final class SeedTests: LeakTrackingTestCase {

    private var dataSeed: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `data() - hex matches data() when given the equivalent hex representation`() throws {
        let expected = try Seed.data(self.dataSeed).data()
        let sut = Seed.hex("3132333435363738393031323334353637383930")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when hex is invalid`() {
        let wrongHex = "3132333435363738393031323334353637383930" + "Z"
        let sut = Seed.hex(wrongHex)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base32 matches data() when given the equivalent base32 representation`() throws {
        let expected = try Seed.data(self.dataSeed).data()
        let sut = Seed.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when base32 is invalid`() {
        let wrongBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" + "1"
        let sut = Seed.base32(wrongBase32)
        #expect(throws: (any Error).self) { try sut.data() }
    }

    @Test
    func `data() - base64 matches data() when given the equivalent base64 representation`() throws {
        let expected = try Seed.data(self.dataSeed).data()
        let sut = Seed.base64("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=")
        #expect(try sut.data() == expected)
    }

    @Test
    func `data() - throws when base64 is invalid`() {
        let wrongBase64 = "MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=" + "!"
        let sut = Seed.base64(wrongBase64)
        #expect(throws: (any Error).self) { try sut.data() }
    }
}
