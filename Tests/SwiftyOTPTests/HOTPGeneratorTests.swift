//
//  HOTPGeneratorTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
@testable import SwiftyOTP

@Suite("HOTPGenerator")
final class HOTPGeneratorTests: LeakTrackingTestCase {

    private var seedData: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    private var rfc4226Vectors: [String] {
        ["755224", "287082", "359152", "969429", "338314",
         "254676", "287922", "162583", "399871", "520489"]
    }

    @Test
    func `init - throws when digits is below the valid range`() {
        #expect(throws: (any Error).self) {
            try HOTPGenerator(seed: .data(self.seedData), digits: 5)
        }
    }

    @Test
    func `init - throws when digits is above the valid range`() {
        #expect(throws: (any Error).self) {
            try HOTPGenerator(seed: .data(self.seedData), digits: 9)
        }
    }

    @Test
    func `otp(at:) - generates RFC 4226 reference vectors`() throws {
        let sut = try HOTPGenerator(seed: .data(seedData))

        for (counter, expected) in rfc4226Vectors.enumerated() {
            let actual = sut.otp(at: UInt64(counter))
            #expect(actual == expected, "counter \(counter)")
        }
    }
}
