//
//  OTPTimerIntegrationTests.swift
//  SwiftyOTPTests
//
//  Exercises `OTPTimer` with a real `TOTPGenerator` and asserts that
//  emitted OTPs match RFC 6238 reference vectors across a window boundary.
//

import Testing
import Foundation
import Clocks
@testable import SwiftyOTP

@MainActor
@Suite("OTPTimer integration")
final class OTPTimerIntegrationTests: LeakTrackingTestCase {

    /// RFC 6238 SHA-1 test seed.
    private var seedSha1: Data {
        "12345678901234567890".data(using: .ascii)!
    }

    @Test
    func `currentOTP - matches RFC 6238 SHA-1 vectors across a window boundary`() async throws {
        // RFC 6238 vectors (8-digit, SHA-1):
        //   t=59 → 94287082 (counter 1)
        //   t=29 → 84755224 (counter 0)
        //
        // Start at t=28 so the first three ticks straddle the t=30 boundary.
        let (sut, clock) = try makeSUT(startingAt: 28)

        await Task.megaYield()

        // Tick 1: now=28, windowChanged=true,  otp = otp(at: 28) = 84755224
        // Tick 2: now=29, windowChanged=false, otp = "84755224" (cached)
        // Tick 3: now=30, windowChanged=true,  otp = otp(at: 30) = 94287082
        await clock.advance(by: .seconds(3))
        await Task.megaYield()

        #expect(sut.currentOTP == "94287082")
    }
}

@MainActor
private extension OTPTimerIntegrationTests {
    func makeSUT(
        startingAt secondsSinceEpoch: TimeInterval,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (sut: OTPTimer, clock: TestClock<Duration>) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let countdown = Countdown(
            timeStep: 30,
            clock: clock,
            dateProvider: { dateBox.next() }
        )
        let provider = try TOTPGenerator(seed: .data(seedSha1), digits: 8, timeStep: 30)
        let sut = OTPTimer(
            countdown: countdown,
            totpProvider: provider,
            startsAutomatically: true
        )
        addTeardownBlock { sut.stop() }
        trackForMemoryLeaks(countdown, sourceLocation: sourceLocation)
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock)
    }
}
