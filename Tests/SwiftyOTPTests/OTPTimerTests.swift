//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
import SwiftyOTP


final class OTPTimerTests: OTPTimerTestCase {
    
    func test_publisher_publishesOTPEventCorrectly() {
        let (sut, _, _) = makeSUT(
            date: Date(timeIntervalSince1970: 28)
        )
        
        expect(sut.publisher, toCatch: [
            .init(countdown: 2, otp: "0"),
            .init(countdown: 1, otp: "0"),
            .init(countdown: 30, otp: "1"),
            .init(countdown: 29, otp: "1"),
        ])
    }
    
}

extension OTPTimerTests {
    private func makeSUT(
        date: Date,
        interval: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (sut: SUT, spy: OTPProviderSpy, countdown: Countdown) {
        let dateProvider = DateProvider(startingDate: date, interval: interval)
        let countdown = Countdown(timeStep: 30, interval: 0, dateProvider: dateProvider.incrementDate)
        let spy = OTPProviderSpy()
        let sut = SUT(countdown: countdown, totpProvider: spy, startsAutomatically: true)
        trackForMemoryLeaks(countdown, file: file, line: line)
        trackForMemoryLeaks(spy, file: file, line: line)
        trackForMemoryLeaks(sut, file: file, line: line)
        return (sut, spy, countdown)
    }
    
    private func getFirstEvents(_ eventNumber: Int, from sut: OTPTimer, after action: () -> Void) -> [OTPTimer.Event] {
        var countdowns = [OTPTimer.Event]()
        let exp = expectation(description: #function)
        
        sut.publisher
            .sink { c in
                countdowns.append(c)
                if countdowns.count == eventNumber {
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)
        
        action()
        wait(for: [exp])
        
        return countdowns
    }
    
    fileprivate final class OTPProviderSpy: TOTPProvider {
        private var count = 0
        
        func otp(intervalSince1970: TimeInterval) -> OTP {
            defer{ count += 1 }
            return "\(count)"
        }
    }
}
