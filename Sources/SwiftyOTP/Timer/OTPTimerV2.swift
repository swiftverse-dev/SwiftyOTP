//
//  OTPTimerV2.swift
//  SwiftyOTP
//
//  V2 of `OTPTimer` — `@MainActor @Observable`, consumes `CountdownV2.ticks`.
//  Renamed to `OTPTimer` at cutover (Phase 5).
//

import Foundation
import Observation

/// `@MainActor`-isolated, `@Observable` driver that updates `currentOTP` and
/// `countdown` from a `CountdownV2`'s tick stream. SwiftUI consumers observe
/// the two stored properties directly. Renamed to `OTPTimer` at the Phase 5
/// cutover of the swift-6 migration.
@MainActor
@Observable
public final class OTPTimerV2 {
    /// OTP window length in seconds (mirrors `CountdownV2.timeStep`).
    public let timeStep: UInt

    /// Latest OTP value emitted by the provider for the current window.
    /// Empty before the first tick is consumed.
    public private(set) var currentOTP: String = ""

    /// Seconds remaining in the current OTP window from the most recent tick.
    /// Zero before the first tick is consumed.
    public private(set) var countdown: TimeInterval = 0

    @ObservationIgnored private let countdownSource: CountdownV2
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
        countdown: CountdownV2,
        totpProvider: any TOTPProvider,
        startsAutomatically: Bool = true
    ) {
        self.countdownSource = countdown
        self.totpProvider = totpProvider
        self.timeStep = countdown.timeStep
        if startsAutomatically { start() }
    }

    /// Starts the consumer task if it is not already running. Idempotent.
    /// Implemented in Phase 3B.
    public func start() {
        // Implemented in Phase 3B.
    }

    /// Cancels the consumer task if any. After calling, observable state
    /// stops being updated. Idempotent. Implemented in Phase 3B.
    public func stop() {
        // Implemented in Phase 3B.
    }

    deinit {
        // Cancellation is nonisolated; safe from `@MainActor` deinit.
        consumerTask?.cancel()
    }
}
