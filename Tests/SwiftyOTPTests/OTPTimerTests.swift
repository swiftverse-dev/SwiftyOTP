//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP


final class OTPTimerTests: XCTestCase {
    
    var cancellables = Set<AnyCancellable>()
    
    override class func setUp() {
        super.setUp()
        setupTimestampIncrement()
    }
    
    override func setUp() {
        super.setUp()
        clearCancellables()
    }

    func test_publisher_publishesOTPChangedEventAsFirstEvent() {
        let expectedOTP = "111 111"
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            interval: 0,
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher, toCatch: [.otpChanged(otp: expectedOTP, countdown: 26.0)]) // 30 - (3 + increment(1)) = 26
    }
    
    func test_publisher_publishesCountDownEventAfterTheFirstEventAndWhenCountdownIsNot30() {
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            interval: 0
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [.countdown(25.0)]) // 30 - (3 + increment(2)) = 25
    }

    func test_publisher_publishesOTPChangedEventWhenTimeWindowChanges() {
        
        let expectedOTP = "111 111"
        let sut = makeSUT(
            date: Date(timeIntervalSince1970: 28),
            interval: 0,
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [.otpChanged(otp: expectedOTP, countdown: 30)]) // 30 - (28 + increment(2)) = 30
    }
}

extension OTPTimerTests {
    private func makeSUT(
        date: Date,
        interval: TimeInterval = 1.0,
        otpProvider: @escaping (TimeInterval) -> TOTPProvider.OTP = { _ in "111 111" },
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> OTPTimer {
        let spy = OTPProviderSpy.init(otpProvider: otpProvider)
        let sut = OTPTimer(startingDate: date, interval: interval, otpProvider: spy)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    private func expect(_ publisher: some Publisher<OTPTimer.Event, Never>, toCatch expectedEvents: [OTPTimer.Event], file: StaticString = #filePath, line: UInt = #line) {
        let exp = expectation(description: "waiting for event")
        exp.expectedFulfillmentCount = expectedEvents.count
        
        var receivedEvents = [OTPTimer.Event]()
        
        publisher.sink{ [weak self] event in
            receivedEvents.append(event)
            exp.fulfill()
            if receivedEvents.count == expectedEvents.count { self?.clearCancellables() }
        }.store(in: &cancellables)

        wait(for: [exp], timeout: 0.01)
        
        XCTAssertEqual(receivedEvents, expectedEvents, file: file, line: line)
    }
    
    private static func setupTimestampIncrement() {
        OTPTimer.incrementTimestamp = { timestamp, _ in timestamp + 1 }
    }
    
    private func clearCancellables() {
        cancellables.removeAll()
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
