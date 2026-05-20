//
//  OTPTimerV2Tests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import Clocks
import os
@testable import SwiftyOTP

@MainActor
@Suite("OTPTimerV2")
final class OTPTimerV2Tests: LeakTrackingTestCase {

    @Test
    func `currentOTP - is empty before any tick is consumed`() async {
        let (sut, _, _) = makeSUT(startsAutomatically: false)

        #expect(sut.currentOTP == "")
        #expect(sut.countdown == 0)
    }

    @Test
    func `init - exposes timeStep from the countdown source`() async {
        let (sut, _, _) = makeSUT(timeStep: 60, startsAutomatically: false)

        #expect(sut.timeStep == 60)
    }
}

@MainActor
private extension OTPTimerV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        startsAutomatically: Bool = true,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: OTPTimerV2, clock: TestClock<Duration>, spy: OTPProviderSpy) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let countdown = CountdownV2(
            timeStep: timeStep,
            clock: clock,
            dateProvider: { dateBox.next() }
        )
        let spy = OTPProviderSpy()
        let sut = OTPTimerV2(
            countdown: countdown,
            totpProvider: spy,
            startsAutomatically: startsAutomatically
        )
        trackForMemoryLeaks(countdown, sourceLocation: sourceLocation)
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock, spy)
    }
}

/// Sendable provider that returns "0", "1", "2", … on successive calls.
/// File-private to this suite.
fileprivate final class OTPProviderSpy: TOTPProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func otp(intervalSince1970: TimeInterval) -> OTP {
        lock.withLock { count in
            defer { count += 1 }
            return "\(count)"
        }
    }
}
