//
//  Item.swift
//  novelit
//
//  Created by 村崎聖仁 on 2026/01/23.
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
