//
//  LeakTrackingTestCase.swift
//  SwiftyOTPTests
//
//  Base class for swift-testing suites that need memory-leak assertions.
//  Subclass and call `trackForMemoryLeaks(_:)` on reference types you want
//  to assert get deallocated by end of test. Swift Testing creates a fresh
//  instance per `@Test`, so `deinit` runs per-test.
//
//  SINGLE-THREADED BY CONTRACT: do not call `addTeardownBlock` from
//  background tasks. Tests that spawn child tasks should ensure those
//  tasks have finished before the test function returns.
//

import Testing

class LeakTrackingTestCase {
    private var teardownBlocks: [() -> Void] = []

    deinit {
        for i in teardownBlocks.indices {
            teardownBlocks[i]()
            // Nil out each block immediately after calling it so that any
            // objects it captures are released before the next block runs.
            // This ensures cleanup actions (e.g. `stop()`) release their
            // targets before the subsequent leak-check blocks fire.
            teardownBlocks[i] = {}
        }
    }

    func addTeardownBlock(_ block: @escaping () -> Void) {
        teardownBlocks.append(block)
    }

    func trackForMemoryLeaks(
        _ instance: AnyObject,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        addTeardownBlock { [weak instance] in
            #expect(
                instance == nil,
                "Instance should have been deallocated. Potential memory leak.",
                sourceLocation: sourceLocation
            )
        }
    }
}
