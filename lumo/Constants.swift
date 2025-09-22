//
//  Constants.swift
//  lumo
//
//  Created by Felix on 2025-09-19.
//


import Foundation

enum Constants {
#if DEBUG
    // Sandbox (development) values
    static let websiteDomain = "http://192.168.1.73:3000"
#else
    // Production values
    static let websiteDomain = "https://lumobc.ca"
#endif
    static let notificationsCheckEndpoint = "/api/notifications/check"
    static let backgroundTaskIdentifier = "com.lumobc.lumo.fetch"
    static let clientIdKeychainKey = "com.lumobc.lumo.clientCookies"
}
