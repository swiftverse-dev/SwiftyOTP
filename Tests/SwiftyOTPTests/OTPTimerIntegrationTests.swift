//
//  OTPTimerIntegrationTests.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP

final class OTPTimerIntegrationTests: OTPTimerTestCase {

    func test_publisher_publishesCorrectOTPsBasedOnSeed() throws {
        let seed = Seed.data(seedSha1)
        let sut = try makeSUT(seed: seed, startingDate: Date(timeIntervalSince1970: 27))
        
        expect(
            sut.publisher,
            toCatch: [
                .otpChanged(otp: "84755224", countdown: 2),
                .countdown(1),
                .otpChanged(otp: "94287082", countdown: 30)
            ]
        )
    }

}


extension OTPTimerIntegrationTests {
    var seedSha1: Data{ "12345678901234567890".data(using: .ascii)! }
    
    private func makeSUT(
        seed: Seed,
        startingDate: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> OTPTimer {
        let provider = try TOTPGenerator(seed: seed, digits: 8)
        let sut = OTPTimer(startingDate: startingDate, interval: 0, otpProvider: provider)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    private static func setupTimestampIncrement() {
        OTPTimer.incrementTimestamp = { timestamp, _ in timestamp + 1 }
    }
    
    private func clearCancellables() {
        cancellables.removeAll()
    }
}
