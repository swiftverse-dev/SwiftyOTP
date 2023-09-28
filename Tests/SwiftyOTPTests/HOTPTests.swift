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
    func test_otpAtCounter_generatesExpectedOTP() throws {
        let seed = Data(hexString: "3132333435363738393031323334353637383930")!
        let expectedOTPs = [
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
        
        let sut = try makeSUT(seed: seed, digits: 6)
        
        expectedOTPs.enumerated().forEach{ i, expectedOTP in
            let otpResult = sut.otp(at: UInt64(i))
            XCTAssertEqual(otpResult, expectedOTP, "For counter \(i) expected otp was \(expectedOTP), got \(otpResult)")
        }
    }
}

// MARK: Helepers
private extension HOTPTests {
    func makeSUT(seed: Data, digits: Int = 6, algo: HashingAlgorithm = .sha1) throws -> HOTP {
        try .init(seed: seed, digits: digits, algorithm: algo)
    }
}
