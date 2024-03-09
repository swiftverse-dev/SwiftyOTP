//
//  File.swift
//  
//
//  Created by Lorenzo Limoli on 09/03/24.
//

import Foundation
import Combine

public final class Countdown {
    public let countdown: UInt
    public let dateProvider: () -> Date
    public let interval: TimeInterval
    public private(set) lazy var publisher = subject.eraseToAnyPublisher()
    
    private(set) var timer: Timer?
    private var windowSize: Double { countdown.asDouble }
    private let subject = PassthroughSubject<TimeInterval, Never>()
    
    public init(countdown: UInt, interval: TimeInterval = 1, dateProvider: @escaping () -> Date = Date.init) {
        self.countdown = countdown
        self.dateProvider = dateProvider
        self.interval = interval
    }
    
    public func start() {
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let countValue = dateProvider().timeIntervalSince1970
                .truncatingRemainder(dividingBy: windowSize)
            subject.send(windowSize - countValue)
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit { stop() }
}
