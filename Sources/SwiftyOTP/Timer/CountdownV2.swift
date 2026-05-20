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
        AsyncStream { continuation in
            let id = UUID()
            let needsStart = state.withLock { state -> Bool in
                state.subscribers[id] = continuation
                return state.producerTask == nil
            }
            if needsStart { startProducer() }
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

    private func startProducer() {
        let task = Task { [weak self] in
            guard let self else { return }
            for await _ in self.clock.timer(interval: .seconds(1)) {
                if Task.isCancelled { return }
                self.broadcastTick()
            }
        }
        state.withLock { $0.producerTask = task }
    }

    private func broadcastTick() {
        let now = dateProvider()
        let windowSize = Double(timeStep)
        let timestamp = now.timeIntervalSince1970
        let currentWindow = UInt(timestamp) / timeStep
        let remainder = timestamp.truncatingRemainder(dividingBy: windowSize)
        let value = windowSize - remainder

        let (tick, subs) = state.withLock { state -> (Tick, [AsyncStream<Tick>.Continuation]) in
            let windowChanged = state.lastWindow.map { currentWindow > $0 } ?? true
            state.lastWindow = currentWindow
            let tick = Tick(value: value, date: now, windowChanged: windowChanged)
            return (tick, Array(state.subscribers.values))
        }

        for sub in subs { sub.yield(tick) }
    }
}
