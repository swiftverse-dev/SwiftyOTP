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
    
    private var timer: Timer?
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

}

private extension CountdownTests {
    func makeSUT(startingDate: Date = Date(timeIntervalSince1970: 0), interval: TimeInterval = 1) -> Countdown {
        let dateProvider = DateProvider(startingDate: startingDate, interval: interval)
        let sut = Countdown(countdown: 30, interval: 0, dateProvider: dateProvider.incrementDate)
        trackForMemoryLeaks(sut)
        return sut
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
        startingDate.addTimeInterval(1)
        return startingDate
        
    }
}