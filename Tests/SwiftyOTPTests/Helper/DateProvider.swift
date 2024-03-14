//
//  DateProvider.swift
//
//
//  Created by Lorenzo Limoli on 14/03/24.
//

import Foundation

final class DateProvider {
    private var startingDate: Date
    private let interval: TimeInterval
    
    init(startingDate: Date, interval: TimeInterval) {
        self.startingDate = startingDate
        self.interval = interval
    }
    
    func incrementDate() -> Date {
        defer { startingDate.addTimeInterval(interval) }
        return startingDate
    }
}
