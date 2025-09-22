import SwiftUI
final class APNSTokenManager {
    static let shared = APNSTokenManager()
    private let deviceTokenKey = "APNSTokenKeychainKey"
    private(set) var deviceToken: String? {
        didSet {
            if let token = deviceToken {
                _ = KeychainHelper.shared.save(data: Data(token.utf8), service: deviceTokenKey)
            } else {
                KeychainHelper.shared.delete(service: deviceTokenKey)
            }
        }
    }
    
    private init() {
        if let data = KeychainHelper.shared.read(service: deviceTokenKey),
           let token = String(data: data, encoding: .utf8) {
            deviceToken = token
        }
    }

    func updateDeviceToken(_ token: String?) {
        self.deviceToken = token
    }
}
