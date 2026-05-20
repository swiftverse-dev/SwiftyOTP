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

    @Test
    func `ticks - reports windowChanged true on the first emission`() async {
        let (sut, clock, _) = makeSUT(startingAt: 0)

        let collected = Task { await sut.ticks.collect(1) }
        await Task.megaYield()
        await clock.advance(by: .seconds(1))
        let ticks = await collected.value

        #expect(ticks.first?.windowChanged == true)
    }

    @Test
    func `ticks - reports windowChanged true when crossing a window boundary`() async {
        // Start at t=27 so the boundary at t=30 falls inside the collected ticks.
        let (sut, clock, _) = makeSUT(startingAt: 27)

        let collected = Task { await sut.ticks.collect(5) }
        await Task.megaYield()
        await clock.advance(by: .seconds(5))
        let ticks = await collected.value

        // DateBox emits 27, 28, 29, 30, 31 across the five ticks.
        // Tick 1: now=27, currentWindow=0, value=30-27=3,  windowChanged=true  (first emission)
        // Tick 2: now=28, currentWindow=0, value=30-28=2,  windowChanged=false
        // Tick 3: now=29, currentWindow=0, value=30-29=1,  windowChanged=false
        // Tick 4: now=30, currentWindow=1, value=30-0=30,  windowChanged=true  (boundary)
        // Tick 5: now=31, currentWindow=1, value=30-1=29,  windowChanged=false
        #expect(ticks.map(\.windowChanged) == [true, false, false, true, false])
        #expect(ticks.map(\.value) == [3, 2, 1, 30, 29])
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
