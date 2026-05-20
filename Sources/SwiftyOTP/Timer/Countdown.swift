//
//  Countdown.swift
//  SwiftyOTP
//
//  swift-clocks-driven countdown source. Broadcasts `Tick` values via
//  `AsyncStream` to multiple subscribers with shared cadence.
//

import Foundation
import os
import Clocks

/// One emission from a `Countdown`: the seconds remaining in the current OTP
/// window, the wall-clock date the tick was produced, and whether this tick
/// crossed a window boundary.
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

/// Lazy, multi-subscriber countdown source driven by a `Clock<Duration>`.
///
/// Each call to `ticks` returns a fresh `AsyncStream<Tick>`. A single
/// producer task starts when the first subscriber begins iterating and is
/// cancelled when the last subscriber drops, so the clock loop only runs
/// while at least one consumer is listening.
public final class Countdown: Sendable {
    /// OTP window length in seconds, as supplied at init.
    public let timeStep: UInt

    private struct State {
        var subscribers: [UUID: AsyncStream<Tick>.Continuation] = [:]
        var producerTask: Task<Void, Never>?
        var lastWindow: UInt?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let clock: any Clock<Duration>
    private let dateProvider: @Sendable () -> Date

    /// Creates a countdown that ticks at one-second cadence on the provided
    /// clock, computing each tick's `value` against `timeStep`.
    ///
    /// - Parameters:
    ///   - timeStep: OTP window length in seconds (typically 30 or 60).
    ///   - clock: Time source for the producer loop. Defaults to
    ///     `ContinuousClock`. Use `TestClock` in tests for deterministic ticks.
    ///   - dateProvider: Source of the `Date` carried by each `Tick`. Inject a
    ///     deterministic provider in tests; defaults to `Date()`.
    public init(
        timeStep: UInt,
        clock: any Clock<Duration> = ContinuousClock(),
        dateProvider: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.timeStep = timeStep
        self.clock = clock
        self.dateProvider = dateProvider
    }

    /// Stream of countdown ticks. Each call returns a fresh `AsyncStream`;
    /// multiple concurrent subscribers receive the same tick payloads with
    /// synchronized cadence.
    public var ticks: AsyncStream<Tick> {
        AsyncStream { continuation in
            let id = UUID()
            state.withLock { state in
                state.subscribers[id] = continuation
                if state.producerTask == nil {
                    // Capture `clock` directly so the task does not pin `self`
                    // strongly across the entire `for await` loop; `self` is
                    // accessed weakly per iteration for `broadcastTick`.
                    let clock = self.clock
                    state.producerTask = Task { [weak self] in
                        for await _ in clock.timer(interval: .seconds(1)) {
                            if Task.isCancelled { return }
                            self?.broadcastTick()
                        }
                    }
                }
            }
            continuation.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        }
    }

    private func unsubscribe(id: UUID) {
        state.withLock { state in
            state.subscribers.removeValue(forKey: id)
            if state.subscribers.isEmpty {
                state.producerTask?.cancel()
                state.producerTask = nil
                state.lastWindow = nil
            }
        }
    }

    private func broadcastTick() {
        let now = dateProvider()
        let windowSize = Double(timeStep)
        let timestamp = now.timeIntervalSince1970
        let currentWindow = UInt(timestamp) / timeStep
        let remainder = timestamp.truncatingRemainder(dividingBy: windowSize)
        let value = windowSize - remainder

        let (tick, subs) = state.withLock { state -> (Tick, [UUID: AsyncStream<Tick>.Continuation].Values) in
            let windowChanged = state.lastWindow.map { currentWindow > $0 } ?? true
            state.lastWindow = currentWindow
            let tick = Tick(value: value, date: now, windowChanged: windowChanged)
            return (tick, state.subscribers.values)
        }

        for sub in subs { sub.yield(tick) }
    }
}
