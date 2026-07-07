//
//  Item.swift
//  Forget It
//
//  Created by Jens Somers on 21/06/2026.
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
