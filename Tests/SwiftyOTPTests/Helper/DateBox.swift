//
//  DateBox.swift
//  SwiftyOTPTests
//
//  Sendable date provider that mints monotonically-increasing one-second
//  steps. Matches the cadence of `clock.timer(interval: .seconds(1))` so
//  tick.date is deterministic when paired with `TestClock`.
//
//  TEST-ONLY. Do NOT copy into Sources/ — CLAUDE.md forbids
//  `@unchecked Sendable` in production code.
//

import Foundation
import os

final class DateBox: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Date>

    init(start: Date) {
        self.lock = OSAllocatedUnfairLock(initialState: start)
    }

    func next() -> Date {
        lock.withLock { current in
            let value = current
            current.addTimeInterval(1)
            return value
        }
    }
}
