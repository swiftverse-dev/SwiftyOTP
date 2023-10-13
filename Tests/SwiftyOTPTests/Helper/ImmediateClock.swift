//
//  ImmediateClock.swift
//
//
//  Created by Lorenzo Limoli on 13/10/23.
//

import Foundation

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
final class ImmediateClock<Duration>: Clock, @unchecked Sendable
where
    Duration: DurationProtocol,
    Duration: Hashable
{
    struct Instant: InstantProtocol {
        var offset: Duration
        init(offset: Duration = .zero) {
            self.offset = offset
        }
        
        func advanced(by duration: Duration) -> Self {
            .init(offset: self.offset + duration)
        }
        
        func duration(to other: Self) -> Duration {
            other.offset - self.offset
        }
        
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }
    
    var now = Instant()
    var minimumResolution = Instant.Duration.zero
    private let lock = NSLock()
    
    init(now: Instant = .init()) {
        self.now = now
    }
    
    func sleep(until deadline: Instant, tolerance: Instant.Duration?) async throws {
        try Task.checkCancellation()
        lock.sync { self.now = deadline }
        await Task.megaYield()
    }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension ImmediateClock where Duration == Swift.Duration {
    convenience init() {
        self.init(now: .init())
    }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension Clock where Self == ImmediateClock<Swift.Duration> {
    /// A clock that does not suspend when sleeping.
    ///
    /// Constructs and returns an ``ImmediateClock``
    ///
    /// > Important: Due to [a bug in Swift](https://github.com/apple/swift/issues/61645), this static
    /// > value cannot be used in an existential context:
    /// >
    /// > ```swift
    /// > let clock: any Clock<Duration> = .immediate  // 🛑
    /// > ```
    /// >
    /// > To work around this bug, construct an immediate clock directly:
    /// >
    /// > ```swift
    /// > let clock: any Clock<Duration> = ImmediateClock()  // ✅
    /// > ```
    static var immediate: Self {
        ImmediateClock()
    }
}

private extension NSLock {
    func sync(_ block: () -> Void) {
        lock()
        defer{ unlock() }
        block()
    }
}

/// The number of yields `Task.megaYield()` invokes by default.
///
/// Can be overridden by setting the `TASK_MEGA_YIELD_COUNT` environment variable.
fileprivate let _defaultMegaYieldCount = max(
    0,
    min(
        ProcessInfo.processInfo.environment["TASK_MEGA_YIELD_COUNT"].flatMap(Int.init) ?? 20,
        10_000
    )
)

private extension Task where Success == Never, Failure == Never {
    /// Suspends the current task a number of times before resuming with the goal of allowing other
    /// tasks to start their work.
    ///
    /// This function can be used to make flakey async tests less flakey, as described in
    /// [this Swift Forums post](https://forums.swift.org/t/reliably-testing-code-that-adopts-swift-concurrency/57304).
    /// You may, however, prefer to use ``withMainSerialExecutor(operation:)-79jpc`` to improve the
    /// reliability of async tests, and to make their execution deterministic.
    ///
    /// > Note: When invoked from ``withMainSerialExecutor(operation:)-79jpc``, or when
    /// > ``uncheckedUseMainSerialExecutor`` is set to `true`, `Task.megaYield()` is equivalent to
    /// > a single `Task.yield()`.
    static func megaYield(count: Int = _defaultMegaYieldCount) async {
        // TODO: Investigate why mega yields are still necessary in TCA's test suite.
        // guard !uncheckedUseMainSerialExecutor else {
        //   await Task.yield()
        //   return
        // }
        for _ in 0..<count {
            await Task<Void, Never>.detached(priority: .background) { await Task.yield() }.value
        }
    }
}
