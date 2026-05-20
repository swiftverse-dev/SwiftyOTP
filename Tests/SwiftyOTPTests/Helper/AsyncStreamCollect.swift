//
//  AsyncStreamCollect.swift
//  SwiftyOTPTests
//
//  Pull the first N values from an AsyncSequence into an array.
//  Pairs with `swift-clocks` `TestClock.advance(by:)` for deterministic tests.
//

import Foundation

extension AsyncSequence where Element: Sendable {
    /// Collect the first `count` elements of this stream into an array.
    /// If the sequence ends before `count` elements arrive, returns what was collected.
    func collect(_ count: Int) async rethrows -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        var iterator = makeAsyncIterator()
        for _ in 0..<count {
            guard let next = try await iterator.next() else { break }
            result.append(next)
        }
        return result
    }
}
