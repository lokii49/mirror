//
//  Item.swift
//  mirror
//
//  Created by Lokesh Pudhari on 25/04/26.
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
