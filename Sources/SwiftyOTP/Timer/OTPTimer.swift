//
//  OTPTimer.swift
//  
//
//  Created by Lorenzo Limoli on 24/10/23.
//

import Foundation
import Combine

/**
 `OTPTimer` Class

 The `OTPTimer` class is responsible for generating and publishing events related to Time-Based One-Time Password (TOTP) countdowns and OTP changes. It leverages the provided `TOTPProvider` to calculate countdowns and OTPs based on a specified time interval.

 Usage:
 - Create an instance of `OTPTimer` with a starting date, time interval, and a conforming `TOTPProvider`.
 - Subscribe to the `publisher` property to receive events related to countdowns and OTP changes.

 Example:
 ```swift
 let totpProvider = MyTOTPProvider()
 let otpTimer = OTPTimer(startingDate: Date(), interval: 30.0, otpProvider: totpProvider)

 otpTimer.publisher.sink { event in
     switch event {
     case .countdown(let countdownInterval):
         // Handle countdown event
         print("Countdown: \(countdownInterval) seconds")
     case .otpChanged(let otp, let countdownInterval):
         // Handle OTP change event
         print("New OTP: \(otp), Countdown: \(countdownInterval) seconds")
     }
 }
*/
public final class OTPTimer {
    public typealias Interval = TimeInterval
    public typealias Publisher = AnyPublisher<Event, Never>
    
    /**
    Enumeration representing different events generated by OTPTimer.

    - `countdown`: Indicates a countdown event with the remaining time interval.
    - `otpChanged`: Indicates an OTP change event along with the countdown time interval.
    */
    public enum Event: Equatable {
        case countdown(Interval)
        case otpChanged(otp: String, countdown: Interval)
    }
    
    /// The publisher that emits events related to countdowns and OTP changes.
    public let publisher: Publisher
    
    /// The timestep configured for the timer
    public var timeStep: UInt { otpProvider.timeStep }
    
    private let otpProvider: TOTPProvider
    
    /**
    Initializes an OTPTimer instance.
     
     - Parameters:
        - startingDate: The starting date for the timer (default is the current date).
        - interval: The time interval (in seconds) at which events are generated (default is 1.0).
        - otpProvider: A TOTPProvider conforming instance for generating OTPs.
    */
    public init(startingDate: Date = .init(), interval: Interval = 1.0, otpProvider: TOTPProvider) {
        self.otpProvider = otpProvider
        self.publisher = Self.timer(every: interval, startingFrom: startingDate, otpProvider: otpProvider)
    }
    
}

extension OTPTimer {
    internal static var incrementTimestamp: (_ timestamp: Interval, _ interval: Interval) -> Interval = { $0 + $1 }
    
    private static func timer(every interval: Interval, startingFrom date: Date, otpProvider: TOTPProvider) -> Publisher {
        let startTime = Date()
        let timestamp = date.timeIntervalSince1970
        var currentStep: UInt64? = nil
        return Timer.publish(every: interval, on: .current, in: .default)
            .autoconnect()
            .scan(timestamp) { timestamp, now in
                // Calculating this time interval should maintain consistency for the timer countdown if the app goes background
                let interval = now.timeIntervalSince(startTime)
                return incrementTimestamp(timestamp, interval) }
            .map{ convertToEvent($0, currentStep: &currentStep, otpProvider: otpProvider) }
            .eraseToAnyPublisher()
    }
    
    private static func convertToEvent(_ timestamp: Interval, currentStep: inout UInt64?, otpProvider: TOTPProvider) -> Event {
        let timeStep = otpProvider.timeStep.asDouble
        let countdown = timeStep - (timestamp.truncatingRemainder(dividingBy: timeStep))
        let newStep = timestamp.asUInt / 30
        if currentStep != newStep {
            currentStep = newStep
            let otp = otpProvider.otp(intervalSince1970: timestamp)
            return .otpChanged(otp: otp, countdown: countdown)
        }
        else {
            return .countdown(countdown)
        }
    }
}
