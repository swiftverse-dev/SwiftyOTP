import XCTest
@testable import SwiftyOTP

final class TOTPTests: XCTestCase {

    let dataSHA1 = "12345678901234567890".data(using: String.Encoding.ascii)!
    let dataSHA256 = "12345678901234567890123456789012".data(using: String.Encoding.ascii)!
    let dataSHA512 = "1234567890123456789012345678901234567890123456789012345678901234".data(using: String.Encoding.ascii)!

    // Test cases taken from https://datatracker.ietf.org/doc/html/rfc6238#appendix-B
    func test01() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds(59)), "94287082")
    }
    
    func test02() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 59)), "46119246")
    }
    
    func test03() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 59)), "90693936")
    }
    
    func test04() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111109)), "07081804")
    }
    
    func test05() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111109)), "68084774")
    }
    
    func test06() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111109)), "25091201")
    }
    
    func test07() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111111)), "14050471")
    }
    
    func test08() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111111)), "67062674")
    }
    
    func test09() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1111111111)), "99943326")
    }
    
    func test10() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1234567890)), "89005924")
    }
    
    func test11() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1234567890)), "91819424")
    }
    
    func test12() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 1234567890)), "93441116")
    }
    
    func test13() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 2000000000)), "69279037")
    }
    
    func test14() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 2000000000)), "90698825")
    }
    
    func test15() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 2000000000)), "38618901")
    }
    
    func test16() throws {
        let sut = try makeSUT(seed: dataSHA1, algo: .sha1)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 20000000000)), "65353130")
    }
    
    func test17() throws {
        let sut = try makeSUT(seed: dataSHA256, algo: .sha256)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 20000000000)), "77737706")
    }
    
    func test18() throws {
        let sut = try makeSUT(seed: dataSHA512, algo: .sha512)
        XCTAssertEqual(sut.otp(unixTimestamp: .seconds( 20000000000)), "47863826")
    }

}

// MARK: HELPERS
extension TOTPTests {
    func makeSUT(seed: Data, timeStep: UInt64 = 30, digits: Int = 8, algo: HashingAlgorithm = .sha1) throws -> TOTP {
        try .init(seed: seed, digits: digits, timeStep: timeStep, algorithm: algo)
    }
}
