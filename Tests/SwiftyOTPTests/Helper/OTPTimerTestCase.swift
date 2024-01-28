//
//  File.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import XCTest
import Combine
@testable import SwiftyOTP

class OTPTimerTestCase: XCTestCase {
    typealias SUT = OTPTimer
    
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        clearCancellables()
        setupTimestampIncrement()
    }
    
    func expect(_ publisher: some Publisher<OTPTimer.Event, Never>, toCatch expectedEvents: [OTPTimer.Event], file: StaticString = #filePath, line: UInt = #line) {
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
    
}

extension OTPTimerTestCase {
    private func setupTimestampIncrement() {
        OTPTimer.incrementTimestamp = { timestamp, _ in timestamp + 1 }
    }
    
    private func clearCancellables() {
        cancellables.removeAll()
    }
}
