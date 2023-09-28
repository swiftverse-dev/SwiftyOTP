//
//  HOTPTests.swift
//  
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import XCTest
@testable import SwiftyOTP

final class HOTPTests: XCTestCase {
    // MARK: Test suite from RFC4226, Appendix D - https://tools.ietf.org/html/rfc4226#page-32
    func test_otpFromHexSeed_generatesExpectedOTP() throws {
        let seed = Seed.data(seedData)
        let sut = try makeSUT(seed: seed)
        
        expectedOTPs.enumerated().forEach{ i, expectedOTP in
            let otpResult = sut.otp(at: UInt64(i))
            XCTAssertEqual(
                otpResult,
                expectedOTP,
                "For counter \(i) expected otp was \(expectedOTP), got \(otpResult)"
            )
        }
    }
}

// MARK: Helepers
private extension HOTPTests {
    var seedData: Data{ "12345678901234567890".data(using: .ascii)! }
    
    var expectedOTPs: [String] {
        [
            "755224",
            "287082",
            "359152",
            "969429",
            "338314",
            "254676",
            "287922",
            "162583",
            "399871",
            "520489"
        ]
    }
    
    func makeSUT(seed: Seed, digits: Int = 6, algo: HashingAlgorithm = .sha1) throws -> HOTP {
        try .init(seed: seed, digits: digits, algorithm: algo)
    }
}
