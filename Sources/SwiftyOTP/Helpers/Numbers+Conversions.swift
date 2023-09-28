//
//  UInt64+AsDouble.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

extension UInt64 {
    var asDouble: Double { Double(self) }
}

extension Double {
    var asUInt: UInt64 { UInt64(self) }
}

extension Float {
    var asUInt32: UInt32 { UInt32(self) }
}
