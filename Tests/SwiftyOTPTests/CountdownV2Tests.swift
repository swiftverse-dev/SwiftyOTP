//
//  CountdownV2Tests.swift
//  SwiftyOTPTests
//

import Testing
import Foundation
import Clocks
@testable import SwiftyOTP

@Suite("CountdownV2")
final class CountdownV2Tests: LeakTrackingTestCase {

    @Test
    func `ticks - emits aligned countdown values at one-second cadence`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        let collected = Task { await sut.ticks.collect(3) }
        await Task.megaYield()
        await clock.advance(by: .seconds(3))
        let ticks = await collected.value

        #expect(ticks.map(\.value) == [30, 29, 28])
    }
}

private extension CountdownV2Tests {
    func makeSUT(
        timeStep: UInt = 30,
        startingAt secondsSinceEpoch: TimeInterval = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> (sut: CountdownV2, clock: TestClock<Duration>, date: DateBox) {
        let clock = TestClock()
        let dateBox = DateBox(start: Date(timeIntervalSince1970: secondsSinceEpoch))
        let sut = CountdownV2(timeStep: timeStep, clock: clock, dateProvider: { dateBox.next() })
        trackForMemoryLeaks(sut, sourceLocation: sourceLocation)
        return (sut, clock, dateBox)
    }
}
