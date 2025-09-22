//
//  RefreshTracker.swift
//  lumo
//
//  Created by Felix on 2025-09-21.
//
import SwiftUI

struct RefreshTracker {
    private static let key = "lastHourlyRefresh"

    static var lastTriggeredAt: Date? {
        get {
            if let timestamp = UserDefaults.standard.object(forKey: key) as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
            return nil
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
            }
        }
    }

    static func shouldRun() -> Bool {
        if let last = lastTriggeredAt {
            return Date().timeIntervalSince(last) >= 3600 // 1 hour
        }
        return true
    }

    static func markTriggered() {
        lastTriggeredAt = Date()
    }
}
