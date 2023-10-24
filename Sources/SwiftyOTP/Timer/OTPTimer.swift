//
//  OTPTimer.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation
import Combine

public final class OTPTimer {
    public typealias Interval = TimeInterval
    public typealias Publisher = AnyPublisher<Event, Never>
    
    public enum Event: Equatable {
        case countdown(Interval)
        case otpChanged(otp: String, countdown: Interval)
    }
    
    public let publisher: Publisher
    
    public init(startingDate: Date = .init(), interval: Interval = 1.0, otpProvider: TOTPProvider) {
        self.publisher = Self.timer(every: interval, startingFrom: startingDate, otpProvider: otpProvider)
    }
    
}

extension OTPTimer {
    internal static var incrementTimestamp: (_ timestamp: Interval, _ interval: Interval) -> Interval = { $0 + $1 }
    
    private static func timer(every interval: Interval, startingFrom date: Date, otpProvider: TOTPProvider) -> Publisher {
        let timestamp = date.timeIntervalSince1970
        var firstCountDown = true
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, _ in incrementTimestamp(timestamp, interval) }
            .map{ convertToEvent($0, firstCountDown: &firstCountDown, otpProvider: otpProvider) }
            .eraseToAnyPublisher()
    }
    
    private static func convertToEvent(_ timestamp: Interval, firstCountDown: inout Bool, otpProvider: TOTPProvider) -> Event {
        let timeStep = otpProvider.timeStep.asDouble
        let countdown = timeStep - (timestamp.truncatingRemainder(dividingBy: timeStep))
        if timeStep - countdown < 0.001 || firstCountDown {
            firstCountDown = false
            let otp = otpProvider.otp(intervalSince1970: timestamp)
            return Event.otpChanged(otp: otp, countdown: countdown)
        }
        else {
            return Event.countdown(countdown)
        }
    }
}
