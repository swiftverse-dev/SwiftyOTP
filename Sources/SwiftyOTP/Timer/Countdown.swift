//
//  File.swift
//  
//
//  Created by Lorenzo Limoli on 09/03/24.
//

import Foundation
import Combine

public final class Countdown {
    
    public enum Event: Equatable {
        case windowChanged(TimeInterval)
        case countdown(TimeInterval)
        
        public var value: TimeInterval {
            switch self {
            case .windowChanged(let timeInterval), .countdown(let timeInterval):
                timeInterval
            }
        }
        
        public func mapValue(_ mapBlock: (TimeInterval) throws -> TimeInterval) rethrows -> Self {
            switch self {
            case .windowChanged(let timeInterval):
                    try .windowChanged(mapBlock(timeInterval))
            case .countdown(let timeInterval):
                try .countdown(mapBlock(timeInterval))
            }
        }
    }
    
    public let countdown: UInt
    public let dateProvider: () -> Date
    public let interval: TimeInterval
    public private(set) lazy var publisher = subject.eraseToAnyPublisher()
    
    private(set) var timer: Timer?
    private var windowSize: Double { countdown.asDouble }
    private let subject = PassthroughSubject<Event, Never>()
    
    public init(countdown: UInt, interval: TimeInterval = 1, dateProvider: @escaping () -> Date = Date.init) {
        self.countdown = countdown
        self.dateProvider = dateProvider
        self.interval = interval
    }
    
    public func start() {
        if timer != nil { return }
        var lastWindow: UInt?
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = dateProvider().timeIntervalSince1970
            
            let currentWindow = UInt(now) / countdown
            let isWindowChanged = lastWindow == nil || currentWindow > lastWindow!
            lastWindow = currentWindow
            
            let countValue = now.truncatingRemainder(dividingBy: windowSize)
            let event = isWindowChanged ? Countdown.Event.windowChanged : Countdown.Event.countdown
            subject.send(event(windowSize - countValue))
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit { stop() }
}
