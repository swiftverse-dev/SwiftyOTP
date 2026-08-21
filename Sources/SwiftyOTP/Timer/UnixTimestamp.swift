//
//  UnixTimestamp.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 21/05/2026.
//

import Foundation

/// A point in time expressed as an offset from the Unix epoch
/// (1970-01-01 00:00:00 UTC), tagged with its unit.
///
/// Used to hand a timestamp to `TOTPProvider.otp(unixTimestamp:)` without
/// ambiguity about whether it is in seconds or milliseconds.
public enum UnixTimestamp: Sendable {
    /// Whole seconds since the Unix epoch.
    case seconds(UInt64)

    /// Whole milliseconds since the Unix epoch.
    case milliseconds(UInt64)

    var timestampInSeconds: TimeInterval {
        switch self {
        case let .seconds(timestamp): TimeInterval(timestamp)
        case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
        }
    }
}
