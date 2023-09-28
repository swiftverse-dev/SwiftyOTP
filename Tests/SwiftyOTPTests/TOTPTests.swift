import XCTest
@testable import SwiftyOTP

final class TOTPTests: XCTestCase {

    let dataSHA1 = "12345678901234567890".data(using: .ascii)!
    let dataSHA256 = "12345678901234567890123456789012".data(using: .ascii)!
    let dataSHA512 = "1234567890123456789012345678901234567890123456789012345678901234".data(using: .ascii)!
    
    
    func test_otp_throwsDigitsOutBoundError() throws {
        XCTAssertThrowsError(try makeSUT(seed: dataSHA1, digits: 5))
        XCTAssertThrowsError(try makeSUT(seed: dataSHA1, digits: 9))
    }
    
    func test_currentOTP_generateExpectedOTP() throws {
        TOTP.currentDateProvider = { Date(timeIntervalSince1970: 59) }
        
        let sutSHA1 = try makeSUT(seed: dataSHA1, algo: .sha1)
        let sutSHA256 = try makeSUT(seed: dataSHA256, algo: .sha256)
        let sutSHA512 = try makeSUT(seed: dataSHA512, algo: .sha512)

        XCTAssertEqual(sutSHA1.currentOTP, "94287082")
        XCTAssertEqual(sutSHA256.currentOTP, "46119246")
        XCTAssertEqual(sutSHA512.currentOTP, "90693936")
    }
    
    // MARK: Test cases taken from https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
    func test_otpSHA1_generateTheExpectedOTP() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        let suite: [(timestamp: UInt64, otp: String)] = [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130")
        ]
        
        assert(sut, tests: suite)
    }
    
    func test_otpSHA256_generateTheExpectedOTP() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        let suite: [(timestamp: UInt64, otp: String)] = [
            (59, "46119246"),
            (1111111109, "68084774"),
            (1111111111, "67062674"),
            (1234567890, "91819424"),
            (2000000000, "90698825"),
            (20000000000, "77737706")
        ]
        
        assert(sut, tests: suite)
    }
    
    func test_otpSHA512_generateTheExpectedOTP() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        let suite: [(timestamp: UInt64, otp: String)] = [
            (59, "90693936"),
            (1111111109, "25091201"),
            (1111111111, "99943326"),
            (1234567890, "93441116"),
            (2000000000, "38618901"),
            (20000000000, "47863826")
        ]
        
        assert(sut, tests: suite)
    }
}

// MARK: HELPERS
private extension TOTPTests {
    func makeSUT(seed: Data, timeStep: UInt64 = 30, digits: Int = 8, algo: HashingAlgorithm = .sha1) throws -> TOTP {
        try .init(seed: seed, digits: digits, timeStep: timeStep, algorithm: algo)
    }
    
    func assert(_ sut: TOTP, tests suite: [(timestamp: UInt64, otp: String)], file: StaticString = #filePath, line: UInt = #line) {
        suite.forEach{ seconds, otp in
            expect(sut, toGenerate: otp, forTimestamp: .seconds(seconds), file: file, line: line)
        }
    }
    
    func expect(
        _ sut: TOTP,
        toGenerate otp: String,
        forTimestamp timestamp: TOTP.UnixTimestamp,
        file: StaticString = #filePath,
        line: UInt = #line) {
            let otpResult = sut.otp(unixTimestamp: timestamp)
            XCTAssertEqual(otpResult, otp, 
                           "For timestamp \(timestamp.timestampInSeconds) expected otp was \(otp), got \(otpResult)",
                           file: file,
                           line: line
            )
    }
}
