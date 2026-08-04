//
//  Item.swift
//  ApiRelay
//
//  Created by 系统之力 on 2026/8/4.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
