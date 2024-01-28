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
    
    func test_publisher_oneSecondIntervalMakeCountdownUpdateEveryOneSecond() throws {
        OTPTimer.incrementTimestamp = { $0 + $1 }
        
        let seed = Seed.data(seedSha1)
        let sut = try makeSUT(
            seed: seed,
            startingDate: Date(timeIntervalSince1970: 27),
            interval: 1
        )
        
        let exp = expectation(description: "")
        var events = [OTPTimer.Event]()
        sut.publisher.sink { event in
            events.append(event)
            if events.count == 3 {
                exp.fulfill()
            }
        }.store(in: &cancellables)
        
        wait(for: [exp], timeout: 5)
        
        events = events.map{ event in
            switch event {
            case .countdown(let interval):
                OTPTimer.Event.countdown(round(interval))
            case .otpChanged(let otp, let countdown):
                OTPTimer.Event.otpChanged(otp: otp, countdown: round(countdown))
            }
        }
        
        XCTAssertEqual(events, [
            .otpChanged(otp: "84755224", countdown: 2),
            .countdown(1),
            .otpChanged(otp: "94287082", countdown: 30)
        ])
    }

}


extension OTPTimerIntegrationTests {
    var seedSha1: Data{ "12345678901234567890".data(using: .ascii)! }
    
    private func makeSUT(
        seed: Seed,
        startingDate: Date,
        interval: TimeInterval = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> OTPTimer {
        let provider = try TOTPGenerator(seed: seed, digits: 8)
        let sut = OTPTimer(startingDate: startingDate, interval: interval, otpProvider: provider)
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
