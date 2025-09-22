//
//  AppDelegate.swift
//  lumo
//
//  Created by Felix on 2025-09-20.
//


import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundTaskManager.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundTaskManager.shared.scheduleAppRefresh()
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map{ String(format: "%02x", $0) }.joined()
        APNSTokenManager.shared.updateDeviceToken(tokenString)

        
        
        NotificationCenter.default.post(name: Notification.Name.didReceiveAPNSToken, object: nil, userInfo: ["token": tokenString])
    }
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Only run if it's a silent push with "content-available": 1
      if let aps = userInfo["aps"] as? [AnyHashable: Any], let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
            BackgroundTaskManager.shared.performHourlyPing()
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // If you support scenes, these can be left empty — SwiftUI handles scene lifecycle
}
