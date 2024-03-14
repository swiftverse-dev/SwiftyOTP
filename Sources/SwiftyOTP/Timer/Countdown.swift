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
        case windowChanged(value: TimeInterval, date: Date)
        case countdown(value: TimeInterval, date: Date)
        
        public var date: Date {
            switch self {
            case .windowChanged(_, let date), .countdown(_, let date):
                date
            }
        }
        
        public var value: TimeInterval {
            switch self {
            case .windowChanged(let timeInterval, _), .countdown(let timeInterval, _):
                timeInterval
            }
        }
        
        public func mapValue(_ mapBlock: (TimeInterval) throws -> TimeInterval) rethrows -> Self {
            switch self {
            case let .windowChanged( timeInterval, date):
                try .windowChanged(value: mapBlock(timeInterval), date: date)
            case let .countdown(timeInterval, date):
                try .countdown(value: mapBlock(timeInterval), date: date)
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
            let now = dateProvider()
            let currentTimestamp = now.timeIntervalSince1970
            
            let currentWindow = UInt(currentTimestamp) / countdown
            let isWindowChanged = lastWindow == nil || currentWindow > lastWindow!
            lastWindow = currentWindow
            
            let countValue = currentTimestamp.truncatingRemainder(dividingBy: windowSize)
            let event = isWindowChanged ? Countdown.Event.windowChanged : Countdown.Event.countdown
            
            let value = windowSize - countValue
            subject.send(event(value, now))
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit { stop() }
}
