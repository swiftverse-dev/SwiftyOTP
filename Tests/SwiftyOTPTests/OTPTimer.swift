//
//  OTPTimer.swift
//  
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import XCTest

final class OTPTimer: XCTestCase {

    func test_publisher_publishFirstEventAsOtpChangedEvent() async throws {
        let clock = ContinuousClock()
        try await clock.sleep(for: .seconds(10))
    }

}
