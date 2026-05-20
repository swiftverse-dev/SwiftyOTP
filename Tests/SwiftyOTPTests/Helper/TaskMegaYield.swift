//
//  TaskMegaYield.swift
//  SwiftyOTPTests
//
//  Cooperative-scheduling helper so producer tasks reach their first
//  `clock.timer`/`clock.sleep` suspension before the test advances time.
//  Mirrors swift-clocks' internal test helper.
//

extension Task where Success == Never, Failure == Never {
    static func megaYield(count: Int = 20) async {
        for _ in 0..<count {
            await Task<Void, Never>.detached(priority: .background) {
                await Task.yield()
            }.value
        }
    }
}
