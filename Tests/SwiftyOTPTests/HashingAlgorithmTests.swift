//
//  HashingAlgorithmTests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import SwiftyOTP

@Suite("HashingAlgorithm")
struct HashingAlgorithmTests {

    @Test
    func `Codable - round-trips every case through its otpauth name`() throws {
        let data = try JSONEncoder().encode(HashingAlgorithm.allCases)
        #expect(String(decoding: data, as: UTF8.self) == #"["SHA1","SHA256","SHA512"]"#)
        #expect(try JSONDecoder().decode([HashingAlgorithm].self, from: data) == HashingAlgorithm.allCases)
    }
}
