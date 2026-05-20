enum UnixTimestamp: Sendable {
        case seconds(UInt64)
        case milliseconds(UInt64)
        
        var timestampInSeconds: TimeInterval {
            switch self {
            case let .seconds(timestamp): TimeInterval(timestamp)
            case let .milliseconds(timestamp): TimeInterval(timestamp) / 1000
            }
        }
    }