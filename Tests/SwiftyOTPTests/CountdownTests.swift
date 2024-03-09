//
//  CountdownTests.swift
//  
//
//  Created by Lorenzo Limoli on 09/03/24.
//

import XCTest
import Combine
@testable import SwiftyOTP

final class Countdown {
    public let countdown: UInt
    public let dateProvider: () -> Date
    public let interval: TimeInterval
    public private(set) lazy var publisher = subject.eraseToAnyPublisher()
    
    private(set) var timer: Timer?
    private var windowSize: Double { countdown.asDouble }
    private let subject = PassthroughSubject<TimeInterval, Never>()
    
    init(countdown: UInt, interval: TimeInterval = 1, dateProvider: @escaping () -> Date = Date.init) {
        self.countdown = countdown
        self.dateProvider = dateProvider
        self.interval = interval
    }
    
    func start() {
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let countValue = dateProvider().timeIntervalSince1970
                .truncatingRemainder(dividingBy: windowSize)
            subject.send(windowSize - countValue)
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit { stop() }
}

final class CountdownTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        cancellables.removeAll()
    }
    
    func test_init_doesNotSendAnyCountdownEvents() {
        let sut = makeSUT()
        
        var countdowns = [Double]()
        sut.publisher.sink { c in
            countdowns.append(c)
        }
        .store(in: &cancellables)
        
        XCTAssertEqual(countdowns, [])
    }

    func test_start_startsSendingCorrectCountdownEvents() {
        let sut = makeSUT()
        let events = getFirstEvents(5, from: sut) {
            sut.start()
        }
            
        XCTAssertEqual(events, [30, 29, 28, 27, 26])
    }
    
    func test_start_restartCountdownCorrectlyAfterWindowChanges() {
        let sut = makeSUT(startingDate: Date(timeIntervalSince1970: 27.5))
        let events = getFirstEvents(5, from: sut) {
                sut.start()
            }
            
        XCTAssertEqual(events, [3, 2, 1, 30, 29])
    }
    
    func test_start_sendsCorrectCountdownEventsForIntervalGreaterThanOne() {
        let sut = makeSUT(interval: 3)
        let events = getFirstEvents(5, from: sut) {
            sut.start()
        }
            
        XCTAssertEqual(events, [30, 27, 24, 21, 18])
    }
    
    func test_stop_stopsTimerCorrectly() {
        let sut = makeSUT()
        var count = 0
        let exp = expectation(description: #function)
        
        sut.publisher.sink { [weak sut] _ in
            count += 1
            if count == 3 {
                sut?.stop()
                exp.fulfill()
            }
        }
        .store(in: &cancellables)
        
        sut.start()
        wait(for: [exp])
        
        XCTAssertEqual(count, 3)
        XCTAssertNil(sut.timer)
    }
    
    func test_stopAndStart_restartTimerCorrectly() {
        let sut = makeSUT(startingDate: Date(timeIntervalSince1970: 27.5))
        let events1 = getFirstEvents(5, from: sut) {
            sut.start()
        }
        
        sut.stop()
        
        let events2 = getFirstEvents(3, from: sut) {
            sut.start()
        }
            
        XCTAssertEqual(events1, [3, 2, 1, 30, 29])
        XCTAssertEqual(events2, [28, 27, 26])
    }
}

private extension CountdownTests {
    func makeSUT(startingDate: Date = Date(timeIntervalSince1970: 0), interval: TimeInterval = 1) -> Countdown {
        let dateProvider = DateProvider(startingDate: startingDate, interval: interval)
        let sut = Countdown(countdown: 30, interval: 0, dateProvider: dateProvider.incrementDate)
        trackForMemoryLeaks(sut)
        return sut
    }
    
    func getFirstEvents(_ eventNumber: Int, from sut: Countdown, after action: () -> Void) -> [TimeInterval] {
        var countdowns = [TimeInterval]()
        let exp = expectation(description: #function)
        
        sut.publisher
            .map{
                $0.rounded(.up)
            }
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
}

private final class DateProvider {
    private var startingDate: Date
    private let interval: TimeInterval
    
    init(startingDate: Date, interval: TimeInterval) {
        self.startingDate = startingDate
        self.interval = interval
    }
    
    func incrementDate() -> Date {
        defer { startingDate.addTimeInterval(interval) }
        return startingDate
    }
}
