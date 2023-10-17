//
//  Numbers+Utils.swift
//  SwiftyOTP
//
//  Created by Lorenzo Limoli on 28/09/23.
//

import Foundation

extension UInt {
    var asDouble: Double { Double(self) }
}

extension Double {
    var asUInt: UInt64 { UInt64(self) }
    var floor: Double { Darwin.floor(self) }
}

extension Float {
    var asUInt32: UInt32 { UInt32(self) }
}
