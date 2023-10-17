//
//  OTPTimerTests.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest
import Combine

public final class OTPTimer {
    public typealias OTP = String
    public typealias CountDown = TimeInterval
    public typealias Publisher = AnyPublisher<Event, Never>
    
    public enum Event: Equatable {
        case countDown(CountDown)
        case otpChanged(otp: String, countDown: CountDown)
    }
    
    public let publisher: Publisher
    
    public init(startingDate: Date = .init(), interval: TimeInterval = 1.0) {
        self.publisher = Self.timer(every: interval, startingFrom: startingDate)
    }
    
    private static func timer(every interval: TimeInterval, startingFrom date: Date) -> Publisher {
        let timestamp = date.timeIntervalSince1970
        var firstCountDown = true
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, _ in timestamp + interval }
            .map{ timestamp in
                let countdown = 30 - (timestamp.truncatingRemainder(dividingBy: 30))
                if countdown == 30 || firstCountDown {
                    firstCountDown = false
                    return Event.otpChanged(otp: "123456", countDown: countdown)
                }
                else {
                    return Event.countDown(countdown)
                }
            }
            .eraseToAnyPublisher()
    }
    
}

final class OTPTimerTests: XCTestCase {
    
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        clearCancellables()
    }

    func test_publisher_publishOTPChangedEventAsFirstEvent() {
        let exp = expectation(description: "waiting for event")
        let sut = makeSUT(date: Date(timeIntervalSince1970: 3), interval: 0)
        
        var receivedEvent = [OTPTimer.Event]()
        sut.publisher.sink{ [weak self] event in
            receivedEvent.append(event)
            self?.clearCancellables()
            exp.fulfill()
        }.store(in: &cancellables)

        wait(for: [exp], timeout: 0.01)
        
        XCTAssertEqual(receivedEvent, [.otpChanged(otp: "123456", countDown: 27.0)])
    }

}

private extension OTPTimerTests {
    func makeSUT(date: Date, interval: TimeInterval = 1.0, file: StaticString = #filePath, line: UInt = #line) -> OTPTimer {
        let sut = OTPTimer(startingDate: date, interval: interval)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    func clearCancellables() {
        cancellables.removeAll()
    }
}
