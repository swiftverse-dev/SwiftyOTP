//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine
import SwiftyOTP

extension TOTPGenerator: OTPProvider {}

public protocol OTPProvider {
    typealias OTP = String
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
    
    private static func timer(every interval: TimeInterval, startingFrom date: Date, otpProvider: OTPProvider) -> Publisher {
        let timestamp = date.timeIntervalSince1970
        var firstCountDown = true
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, _ in timestamp + interval }
            .map{ convertToEvent($0, firstCountDown: &firstCountDown, otpProvider: otpProvider) }
            .eraseToAnyPublisher()
    }
    
    private static func convertToEvent(_ timestamp: Countdown, firstCountDown: inout Bool, otpProvider: OTPProvider) -> Event {
        let countdown = 30 - (timestamp.truncatingRemainder(dividingBy: 30))
        if countdown == 30 || firstCountDown {
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
        
        let exp = expectation(description: "waiting for event")
        var receivedEvents = [OTPTimer.Event]()
        sut.publisher.sink{ [weak self] event in
            receivedEvents.append(event)
            self?.clearCancellables()
            exp.fulfill()
        }.store(in: &cancellables)

        wait(for: [exp], timeout: 0.01)
        
        XCTAssertEqual(receivedEvents, [.otpChanged(otp: expectedOTP, countdown: 27.0)])
    }
    
    func test_publisher_publishCountDownEventAfterTheFirstAndWhenCountdownIsNot30() {
        let (sut, _) = makeSUT(
            date: Date(timeIntervalSince1970: 3),
            interval: 0
        )
        
        let exp = expectation(description: "waiting for event")
        var receivedEvents = [OTPTimer.Event]()
        sut.publisher
            .dropFirst()
            .sink{ [weak self] event in
                receivedEvents.append(event)
                self?.clearCancellables()
                exp.fulfill()
            }.store(in: &cancellables)

        wait(for: [exp], timeout: 0.01)
        
        XCTAssertEqual(receivedEvents, [.countdown(27.0)])
    }

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
    
    private func clearCancellables() {
        cancellables.removeAll()
    }
    
    private struct OTPProviderSpy: OTPProvider {
        private let otpProvider: (TimeInterval) -> OTPProvider.OTP
        
        init(otpProvider: @escaping (TimeInterval) -> OTPProvider.OTP) {
            self.otpProvider = otpProvider
        }
        
        func otp(intervalSince1970: TimeInterval) -> OTP { otpProvider(intervalSince1970) }
    }
}
