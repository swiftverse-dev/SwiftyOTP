//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP


final class OTPTimerTests: OTPTimerTestCase {

    func test_publisher_publishesOTPChangedEventAsFirstEvent() {
        let expectedOTP = "111111"
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher, toCatch: [.otpChanged(otp: expectedOTP, countdown: 27.0)])
    }
    
    func test_publisher_publishesCountDownEventAfterTheFirstEventAndWhenCountdownIsNot30() {
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 3)
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [.countdown(26.0)])
    }

    func test_publisher_publishesOTPChangedEventWhenTimeWindowChanges() {
        
        let expectedOTP = "111 111"
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 29),
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [.otpChanged(otp: expectedOTP, countdown: 30)])
    }
    
    func test_publisher_publishesOTPChangedEventWhenTimeWindowChangesWithoutPassingFromZero() {

        let expectedOTP = "111 111"
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 28),
            interval: 4,
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [
            .otpChanged(otp: expectedOTP, countdown: 28),
        ])
    }
}

extension OTPTimerTests {
    private func makeSUT(
        date: Date,
        interval: TimeInterval = 1.0,
        otpProvider: @escaping (TimeInterval) -> TOTPProvider.OTP = { _ in "111111" },
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SUT {
        let dateProvider = DateProvider(startingDate: date, interval: interval)
        let countdown = Countdown(timeStep: 30, interval: 0, dateProvider: dateProvider.incrementDate)
        let spy = OTPProviderSpy.init(otpProvider: otpProvider)
        let sut = SUT(countdown: countdown, totpProvider: spy, startsAutomatically: false)
        trackForMemoryLeaks(countdown, file: file, line: line)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    private struct OTPProviderSpy: TOTPProvider {
        private let otpProvider: (TimeInterval) -> TOTPProvider.OTP
        let timeStep: UInt
        
        init(timeStep: UInt = 30, otpProvider: @escaping (TimeInterval) -> TOTPProvider.OTP) {
            self.otpProvider = otpProvider
            self.timeStep = timeStep
        }
        
        func otp(intervalSince1970: TimeInterval) -> OTP { otpProvider(intervalSince1970) }
    }
}
