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

    @Test
    func `start - updates currentOTP from provider on first tick`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        await Task.megaYield()
        await clock.advance(by: .seconds(1))
        await Task.megaYield()

        #expect(sut.currentOTP == "0")
    }

    @Test
    func `currentOTP - changes only when the window boundary is crossed`() async {
        let (sut, clock, _) = makeSUT(startingAt: 27)

        await Task.megaYield()
        // Tick 1 (now=27, windowChanged=true) → otp "0"
        await clock.advance(by: .seconds(1))
        await Task.megaYield()
        let firstOTP = sut.currentOTP

        // Tick 2 (now=28, windowChanged=false) → reuse "0"
        await clock.advance(by: .seconds(1))
        await Task.megaYield()
        let sameWindowOTP = sut.currentOTP

        // Tick 3 (now=29, windowChanged=false) → reuse "0"
        await clock.advance(by: .seconds(1))
        await Task.megaYield()
        let stillSameOTP = sut.currentOTP

        // Tick 4 (now=30, windowChanged=true) → otp "1"
        await clock.advance(by: .seconds(1))
        await Task.megaYield()
        let nextWindowOTP = sut.currentOTP

        #expect(firstOTP == "0")
        #expect(sameWindowOTP == "0")
        #expect(stillSameOTP == "0")
        #expect(nextWindowOTP == "1")
    }

    @Test
    func `countdown - mirrors the latest tick value`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        await Task.megaYield()
        await clock.advance(by: .seconds(3))
        await Task.megaYield()

        // Last tick at now=2 → countdown = 30 - 2 = 28
        #expect(sut.countdown == 28)
    }

    @Test
    func `start - is idempotent when called twice`() async {
        let (sut, clock, _) = makeSUT(startsAutomatically: false)

        sut.start()
        sut.start()

        await Task.megaYield()
        await clock.advance(by: .seconds(1))
        await Task.megaYield()

        // If two consumer tasks were running, the spy would emit "0" then "1" on
        // the same tick. Only one consumer task should be running, so currentOTP == "0".
        #expect(sut.currentOTP == "0")
    }

    @Test
    func `stop - stops updating observable state`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        await Task.megaYield()
        await clock.advance(by: .seconds(1))
        await Task.megaYield()
        let beforeStop = sut.currentOTP

        sut.stop()

        await clock.advance(by: .seconds(60))
        await Task.megaYield()
        let afterStop = sut.currentOTP

        #expect(beforeStop == afterStop)
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
        addTeardownBlock { sut.stop() }
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
