//
//  CountdownV2.swift
//  SwiftyOTP
//
//  V2 of `Countdown` — swift-clocks-driven, broadcasts ticks via AsyncStream.
//  Renamed to `Countdown` at cutover (Phase 5).
//

import Foundation
import os
import Clocks

public struct Tick: Sendable, Equatable {
    public let value: TimeInterval
    public let date: Date
    public let windowChanged: Bool

    public init(value: TimeInterval, date: Date, windowChanged: Bool) {
        self.value = value
        self.date = date
        self.windowChanged = windowChanged
    }
}

public final class CountdownV2: Sendable {
    public let timeStep: UInt

    fileprivate struct State {
        var subscribers: [UUID: AsyncStream<Tick>.Continuation] = [:]
        var producerTask: Task<Void, Never>?
        var lastWindow: UInt?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let clock: any Clock<Duration>
    private let dateProvider: @Sendable () -> Date

    public init(
        timeStep: UInt,
        clock: any Clock<Duration> = ContinuousClock(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.timeStep = timeStep
        self.clock = clock
        self.dateProvider = dateProvider
    }

    public var ticks: AsyncStream<Tick> {
        AsyncStream { _ in }   // Implemented in Task 2.2.
    }
}
