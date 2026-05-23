//
//  UnixTimestamp.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 21/05/2026.
//

import Foundation

public enum UnixTimestamp: Sendable {
    case seconds(UInt64)
    case milliseconds(UInt64)

    var timestampInSeconds: TimeInterval {
        switch self {
        case let .seconds(timestamp): TimeInterval(timestamp)
        case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
        }
    }
}
