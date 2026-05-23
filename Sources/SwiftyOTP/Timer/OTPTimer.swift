//
//  OTPTimer.swift
//  SwiftyOTP
//
//  `@MainActor @Observable` driver that exposes the current OTP and
//  countdown derived from a `Countdown`'s tick stream.
//

import Foundation
import Observation

/// `@MainActor`-isolated, `@Observable` driver that updates `currentOTP` and
/// `countdown` from a `Countdown`'s tick stream. SwiftUI consumers observe
/// the two stored properties directly.
@MainActor
@Observable
public final class OTPTimer {
    /// OTP window length in seconds (mirrors `Countdown.timeStep`).
    public let timeStep: UInt

    /// Latest OTP value emitted by the provider for the current window.
    /// Empty before the first tick is consumed.
    public private(set) var currentOTP: String = ""

    /// Seconds remaining in the current OTP window from the most recent tick.
    /// Zero before the first tick is consumed.
    public private(set) var countdown: TimeInterval = 0

    @ObservationIgnored private let countdownSource: Countdown
    @ObservationIgnored private let totpProvider: any TOTPProvider
    @ObservationIgnored private var consumerTask: Task<Void, Never>?
    @ObservationIgnored private var lastOTP: String?

    /// Creates an OTP timer driven by the supplied countdown source.
    ///
    /// - Parameters:
    ///   - countdown: Tick source.
    ///   - totpProvider: OTP-generation hook called when a tick reports a
    ///     window boundary (or on the very first tick).
    ///   - startsAutomatically: When `true` (default), the consumer task is
    ///     spawned in `init` so observers see updates as soon as the clock
    ///     produces ticks. Set to `false` to defer the first tick until
    ///     `start()` is called explicitly.
    public init(
        countdown: Countdown,
        totpProvider: any TOTPProvider,
        startsAutomatically: Bool = true
    ) {
        self.countdownSource = countdown
        self.totpProvider = totpProvider
        self.timeStep = countdown.timeStep
        if startsAutomatically { start() }
    }

    /// Starts the consumer task if not already running. Idempotent.
    public func start() {
        guard consumerTask == nil else { return }
        let stream = countdownSource.ticks
        consumerTask = Task { @MainActor [weak self] in
            for await tick in stream {
                if Task.isCancelled { break }
                guard let self else { break }
                self.handle(tick: tick)
            }
        }
    }

    /// Cancels the consumer task if any. After calling, observable state
    /// stops being updated. Idempotent.
    public func stop() {
        consumerTask?.cancel()
        consumerTask = nil
    }

    private func handle(tick: Tick) {
        let otp = if tick.windowChanged || lastOTP == nil {
            totpProvider.otp(intervalSince1970: tick.date.timeIntervalSince1970)
        } else {
            lastOTP ?? ""
        }
        lastOTP = otp
        currentOTP = otp
        countdown = tick.value
    }

    deinit {
        consumerTask?.cancel()
    }
}
