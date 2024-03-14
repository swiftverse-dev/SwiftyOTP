//
//  CountdownTests.swift
//  
//
//  Created by Lorenzo Limoli on 09/03/24.
//

import XCTest
import Combine
@testable import SwiftyOTP

final class CountdownTests: XCTestCase {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        cancellables.removeAll()
    }
    
    func test_init_doesNotSendAnyCountdownEvents() {
        let sut = makeSUT()
        
        var countdowns = [Countdown.Event]()
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
            .map(\.value)
            
        XCTAssertEqual(events, [30, 29, 28, 27, 26])
    }
    
    func test_start_restartCountdownCorrectlyAfterWindowChanges() {
        let sut = makeSUT(startingDate: Date(timeIntervalSince1970: 27.5))
        let events = getFirstEvents(5, from: sut) {
            sut.start()
        }
            .map(\.value)
            
        XCTAssertEqual(events, [3, 2, 1, 30, 29])
    }
    
    func test_start_sendsCorrectCountdownEventsForIntervalGreaterThanOne() {
        let sut = makeSUT(interval: 3)
        let events = getFirstEvents(5, from: sut) {
            sut.start()
        }
            .map(\.value)
            
        XCTAssertEqual(events, [30, 27, 24, 21, 18])
    }
    
    func test_start_sendsCorrectWindowChangedEventsWhenWindowChanges() {
        let sut = makeSUT(startingDate: Date(timeIntervalSince1970: 27.5))
        let events = getFirstEvents(5, from: sut) {
            sut.start()
        }
        
        let expectedEvents = [
            Countdown.Event.windowChanged(value: 3, date: Date(timeIntervalSince1970: 27.5)),
            Countdown.Event.countdown(value: 2, date: Date(timeIntervalSince1970: 28.5)),
            Countdown.Event.countdown(value: 1, date: Date(timeIntervalSince1970: 29.5)),
            Countdown.Event.windowChanged(value: 30, date: Date(timeIntervalSince1970: 30.5)),
            Countdown.Event.countdown(value: 29, date: Date(timeIntervalSince1970: 31.5)),
        ]
            
        XCTAssertEqual(events, expectedEvents)
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
            .map(\.value)
        
        sut.stop()
        
        let events2 = getFirstEvents(3, from: sut) {
            sut.start()
        }
            .map(\.value)
            
        XCTAssertEqual(events1, [3, 2, 1, 30, 29])
        XCTAssertEqual(events2, [28, 27, 26])
    }
}

private extension CountdownTests {
    func makeSUT(
        startingDate: Date = Date(timeIntervalSince1970: 0),
        interval: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Countdown {
        let dateProvider = DateProvider(startingDate: startingDate, interval: interval)
        let sut = Countdown(timeStep: 30, interval: 0, dateProvider: dateProvider.incrementDate)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    func getFirstEvents(_ eventNumber: Int, from sut: Countdown, after action: () -> Void) -> [Countdown.Event] {
        var countdowns = [Countdown.Event]()
        let exp = expectation(description: #function)
        
        sut.publisher
            .map{
                $0.mapValue({ $0.rounded(.up) })
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
