//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP

public protocol OTPProvider {
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
    
    public init(startingDate: Date = .init(), interval: TimeInterval = 1.0, otpProvider: OTPProvider) {
        self.publisher = Self.timer(every: interval, startingFrom: startingDate, otpProvider: otpProvider)
    }
    
}

extension OTPTimer {
    internal static var incrementTimestamp: (_ timestamp: Countdown, _ interval: Countdown) -> Countdown = { $0 + $1 }
    
    private static func timer(every interval: TimeInterval, startingFrom date: Date, otpProvider: OTPProvider) -> Publisher {
        let timestamp = date.timeIntervalSince1970
        var firstCountDown = true
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, _ in incrementTimestamp(timestamp, interval) }
            .map{ convertToEvent($0, firstCountDown: &firstCountDown, otpProvider: otpProvider) }
            .eraseToAnyPublisher()
    }
    
    private static func convertToEvent(_ timestamp: Countdown, firstCountDown: inout Bool, otpProvider: OTPProvider) -> Event {
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
    
    override func setUp() {
        super.setUp()
        clearCancellables()
    }

    func test_publisher_publishOTPChangedEventAsFirstEvent() {
        let expectedOTP = "111 111"
        let (sut, _) = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            interval: 0,
            otpProvider: { _ in expectedOTP }
        )
        
        expect(sut.publisher, toCatch: [.otpChanged(otp: expectedOTP, countdown: 27.0)])
    }
    
    func test_publisher_publishCountDownEventAfterTheFirstAndWhenCountdownIsNot30() {
        let (sut, _) = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            interval: 0
        )
        
        expect(sut.publisher.dropFirst(), toCatch: [.countdown(27.0)])
    }

//    func test_publisher_publishOTPChangedAndCountdownEventsBasedOn
}

extension OTPTimerTests {
    private func makeSUT(
        date: Date,
        interval: TimeInterval = 1.0,
        otpProvider: @escaping (TimeInterval) -> OTPProvider.OTP = { _ in "111 111" },
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (sut: OTPTimer, spy: OTPProviderSpy) {
        let spy = OTPProviderSpy.init(otpProvider: otpProvider)
        let sut = OTPTimer(startingDate: date, interval: interval, otpProvider: spy)
        trackForMemoryLeaks(sut, file: file, line: line)
        return (sut, spy)
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
    
    private func clearCancellables() {
        cancellables.removeAll()
    }
    
    private struct OTPProviderSpy: OTPProvider {
        private let otpProvider: (TimeInterval) -> OTPProvider.OTP
        let timeStep: UInt
        
        init(timeStep: UInt = 30, otpProvider: @escaping (TimeInterval) -> OTPProvider.OTP) {
            self.otpProvider = otpProvider
            self.timeStep = timeStep
        }
        
        func otp(intervalSince1970: TimeInterval) -> OTP { otpProvider(intervalSince1970) }
    }
}
