//
//  SeedTests.swift
//
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import XCTest
@testable import SwiftyOTP

final class SeedTests: XCTestCase {
    
    func test_seedFromHex_matchData() throws {
        let expectedData = try Seed.data(dataSeed).data()
        let sut = Seed.hex("3132333435363738393031323334353637383930")
        XCTAssertEqual(try sut.data(), expectedData)
    }
    
    func test_seedFromHex_throwsInvalidEncodingErrorForInvalidHexRepresentation() {
        let wrongHex = "3132333435363738393031323334353637383930" + "Z"
        let sut = Seed.hex(wrongHex)
        XCTAssertThrowsError(try sut.data())
    }
    
    func test_seedFromBase32_matchData() throws {
        let expectedData = try Seed.data(dataSeed).data()
        let sut = Seed.base32("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        XCTAssertEqual(try sut.data(), expectedData)
    }
    
    func test_seedFromBase32_throwsInvalidEncodingErrorForInvalidBase32Representation() {
        let wrongBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" + "1"
        let sut = Seed.base32(wrongBase32)
        XCTAssertThrowsError(try sut.data())
    }
    
    func test_seedFromBase64_matchData() throws {
        let expectedData = try Seed.data(dataSeed).data()
        let sut = Seed.base64("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=")
        XCTAssertEqual(try sut.data(), expectedData)
    }
    
    func test_seedFromBase64_throwsInvalidEncodingErrorForInvalidBase64Representation() {
        let wrongBase64 = String("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA=" + "!")
        let sut = Seed.base64(wrongBase64)
        XCTAssertThrowsError(try sut.data())
    }
}

// MARK: HELPERS
extension SeedTests {
    var dataSeed: Data{ "12345678901234567890".data(using: .ascii)! }
}

