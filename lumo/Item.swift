//
//  Item.swift
//  lumo
//
//  Created by Felix on 2025-09-19.
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
