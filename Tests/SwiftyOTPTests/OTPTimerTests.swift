//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP

public protocol TOTPProvider {
    typealias OTP = String
    var timeStep: UInt { get }
    func otp(intervalSince1970: TimeInterval) -> OTP
}

public final class OTPTimer {
    public typealias Countdown = TimeInterval
    public typealias Publisher = AnyPublisher<Event, Never>
    
    public enum Event: Equatable {
        case countdown(Countdown)
        case otpChanged(otp: String, countdown: Countdown)
    }
    
    public let publisher: Publisher
    
    public init(startingDate: Date = .init(), interval: TimeInterval = 1.0, otpProvider: TOTPProvider) {
        self.publisher = Self.timer(every: interval, startingFrom: startingDate, otpProvider: otpProvider)
    }
    
}

extension OTPTimer {
    internal static var incrementTimestamp: (_ timestamp: Countdown, _ interval: Countdown) -> Countdown = { $0 + $1 }
    
    private static func timer(every interval: TimeInterval, startingFrom date: Date, otpProvider: TOTPProvider) -> Publisher {
        let timestamp = date.timeIntervalSince1970
        var firstCountDown = true
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, _ in incrementTimestamp(timestamp, interval) }
            .map{ convertToEvent($0, firstCountDown: &firstCountDown, otpProvider: otpProvider) }
            .eraseToAnyPublisher()
    }
    
    private static func convertToEvent(_ timestamp: Countdown, firstCountDown: inout Bool, otpProvider: TOTPProvider) -> Event {
        let timeStep = otpProvider.timeStep.asDouble
        let countdown = timeStep - (timestamp.truncatingRemainder(dividingBy: timeStep))
        if timeStep - countdown < 0.001 || firstCountDown {
            firstCountDown = false
            let otp = otpProvider.otp(intervalSince1970: timestamp)
            return Event.otpChanged(otp: otp, countdown: countdown)
        }
        else {
            return Event.countdown(countdown)
        }
    }
}

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
