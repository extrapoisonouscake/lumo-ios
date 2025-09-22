// MARK: - Notification.Name Extension
extension Notification.Name {
    static let didReceiveAPNSToken = Notification.Name("didReceiveAPNSToken")
}

import SwiftUI
import WebKit
import UserNotifications


struct WebViewContainer: UIViewRepresentable {
    let urlString: String = Constants.websiteDomain

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let userController = WKUserContentController()

        // Inject JS bridge
        let scriptSource = """
        window.__nativeCallback = window.__nativeCallback || function() {};
        """
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userController.addUserScript(userScript)

        userController.add(context.coordinator, name: "native")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Loading overlay
        context.coordinator.loadingView = context.coordinator.createLoadingView()
        if let overlay = context.coordinator.loadingView {
            webView.addSubview(overlay)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: webView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
            ])
        }

        // Load URL
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var loadingView: UIView?
        private var apnsTokenCallbackName: String?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            let callbackName = body["callbackName"] as? String

            switch action {
            case "requestNotificationPermission":
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    self.sendCallback(callbackName: callbackName, result: granted ? "granted" : "denied")
                }
            case "checkNotificationsRegistered":
                DispatchQueue.main.async {
                    let isRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
                    self.sendCallback(callbackName: callbackName, result: isRegistered ? "true" : "false")
                }
            case "registerForNotifications":
                DispatchQueue.main.async {
                    
                    if let token = APNSTokenManager.shared.deviceToken {
                        
                        // Return the device token to JS
                        self.sendCallback(callbackName: callbackName, result: token)
                    } else {
                        
                        // Trigger APNs registration
                        UIApplication.shared.registerForRemoteNotifications()
                        // Registration not completed yet
                        self.apnsTokenCallbackName = callbackName
                        NotificationCenter.default.addObserver(self, selector: #selector(self.didReceiveAPNSTokenNotification(_:)), name: Notification.Name.didReceiveAPNSToken, object: nil)
                    }
                }
            case "unregisterFromNotifications":
                DispatchQueue.main.async {
                    UIApplication.shared.unregisterForRemoteNotifications()
                    // Optionally clear stored APNs token
                    APNSTokenManager.shared.updateDeviceToken(nil)
                    self.sendCallback(callbackName: callbackName, result: "ok")
                }
            case "checkNotificationPermission":
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    let result: String
                    switch settings.authorizationStatus {
                    case .authorized, .provisional: result = "granted"
                    case .denied: result = "denied"
                    case .notDetermined: result = "notDetermined"
                    default: result = "notDetermined"
                    }
                    self.sendCallback(callbackName: callbackName, result: result)
                }
            case "getAppTheme":
                let currentTheme = getThemeColorString()
                self.sendCallback(callbackName: callbackName, result: currentTheme)

            case "setAppTheme":
                guard let hsl = body["hsl"] as? String else {
                    self.sendCallback(callbackName: callbackName, result: "error")
                    break
                }
                let themeMap: [String: String?] = [
                    "162 23.3% 45.7%":nil,
                    "350 72% 52%":"RedAppIcon",
                    "338 49% 43%":"BurgundyAppIcon",
                    "345 100% 78%":"PinkAppIcon",
                    "31 100% 48%":"OrangeAppIcon",
                    "40 97% 64%":"YellowAppIcon",
                    "90 34% 63%":"LightGreenAppIcon",
                    "201 100% 36%":"BlueAppIcon",
                    "206 46% 37%":"NavyAppIcon",
                    "239 77% 70%":"PurpleAppIcon"
                   
                ]
                
                if themeMap.keys.contains(hsl) {
                    let iconName = themeMap[hsl] ?? nil
                    if UIApplication.shared.supportsAlternateIcons {
                        UIApplication.shared.setAlternateIconName(iconName) { error in
                            let iconSuccess = (error == nil)
                            UserDefaults.standard.set(hsl, forKey: "themeColor")
                            self.sendCallback(callbackName: callbackName, result: iconSuccess ? "success" : "error")
                        }
                    } else{
                        self.sendCallback(callbackName: callbackName, result: "error")
                    }
                } else {
                    self.sendCallback(callbackName: callbackName, result: "error")
                }

            case "storeEncryptedCookies":
                if let b64 = body["payload"] as? String, let data = Data(base64Encoded: b64) {
                    _ = KeychainHelper.shared.save(data: data, service: Constants.clientIdKeychainKey)
                    self.sendCallback(callbackName: callbackName, result: "ok")
                }

            case "logoutWipe":
                KeychainHelper.shared.delete(service: Constants.clientIdKeychainKey)
                let dataStore = WKWebsiteDataStore.default()
                dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                    dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                        DispatchQueue.main.async {
                            if let url = URL(string: Constants.websiteDomain) {
                                self.webView?.load(URLRequest(url: url))
                            }
                            self.sendCallback(callbackName: callbackName, result: "ok")
                        }
                    }
                }

            case "activateCron":
                
                
                let cookieStore = self.webView!.configuration.websiteDataStore.httpCookieStore
                cookieStore.getAllCookies { cookies in
                    if let studentId = cookies.first(where: { $0.name == "auth.studentId" })?.value,
                       let credentials = cookies.first(where: { $0.name == "auth.credentials" })?.value {
                        BackgroundTaskManager.shared.activate(studentId: studentId, credentials: credentials)
                        self.sendCallback(callbackName: callbackName, result: "ok")
                    } else {
                        self.sendCallback(callbackName: callbackName, result: "error")
                        
                    }
                   
                }

            case "deactivateCron":
                
                BackgroundTaskManager.shared.deactivate()
                self.sendCallback(callbackName: callbackName, result: "ok")

            default:
                self.sendCallback(callbackName: callbackName, result: "unknown_action")
            }
        }

        @objc private func didReceiveAPNSTokenNotification(_ notification: Notification) {
            
            guard let token = notification.userInfo?["token"] as? String,
                  let callbackName = apnsTokenCallbackName else { return }
            APNSTokenManager.shared.updateDeviceToken(token)
            sendCallback(callbackName: callbackName, result: token)
            apnsTokenCallbackName = nil
            NotificationCenter.default.removeObserver(self, name: Notification.Name.didReceiveAPNSToken, object: nil)
        }

        private func sendCallback(callbackName: String?, result: String) {
            guard let callbackName = callbackName else { return }
            let js = "window.__nativeCallback('\(callbackName)', '\(result)')"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // MARK: - Navigation delegate
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let overlay = loadingView {
                UIView.animate(withDuration: 0.4, animations: { overlay.alpha = 0 }) { _ in
                    overlay.removeFromSuperview()
                    self.loadingView = nil
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showErrorOverlay(message: "Failed to load page. Please check your connection.")
            print("Provisional load failed:", error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showErrorOverlay(message: "Failed to load page. Please check your connection.")
            print("Navigation failed:", error.localizedDescription)
        }

        private func showErrorOverlay(message: String) {
            guard let webView = webView else { return }
            loadingView?.removeFromSuperview()

            let overlay = UIView()
            overlay.backgroundColor = .systemBackground
            overlay.alpha = 0.95

            let label = UILabel()
            label.numberOfLines = 0
            label.textColor = .label
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false

            // Set attributed text with increased line spacing
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            let attributedString = NSAttributedString(string: message, attributes: [
                .paragraphStyle: paragraphStyle
            ])
            label.attributedText = attributedString

            overlay.addSubview(label)

            // Add reload button below the label
            let reloadButton = UIButton(type: .system)
            reloadButton.setTitle("Reload", for: .normal)
            reloadButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            reloadButton.translatesAutoresizingMaskIntoConstraints = false
            reloadButton.addTarget(self, action: #selector(reloadWebView), for: .touchUpInside)
            overlay.addSubview(reloadButton)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                label.topAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -30),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -20),

                reloadButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
                reloadButton.centerXAnchor.constraint(equalTo: overlay.centerXAnchor)
            ])

            webView.addSubview(overlay)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: webView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
            ])

            self.loadingView = overlay
        }

        @objc private func reloadWebView() {
            loadingView?.removeFromSuperview()
            loadingView = createLoadingView()
            if let overlay = loadingView, let webView = webView {
                webView.addSubview(overlay)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    overlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
                    overlay.topAnchor.constraint(equalTo: webView.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
                ])
            }
            if let url = webView?.url {
                webView?.load(URLRequest(url: url))
            } else if let url = URL(string: Constants.websiteDomain) {
                webView?.load(URLRequest(url: url))
            }
        }

        func createLoadingView() -> UIView {
            let overlay = UIView()
            overlay.backgroundColor = .systemBackground

            let logo = UIImageView()
            logo.contentMode = .scaleAspectFit
            logo.translatesAutoresizingMaskIntoConstraints = false
            // Load SVG asset as UIImage and apply tint color based on themeColor in UserDefaults
            let themeColorString = getThemeColorString()
            
            let themeColor = UIColor.fromHSLString(themeColorString)
            
            // Assume SVG is in assets as "AppLogoSVG"
            if let svgImage = UIImage(named: "AppLogoSVG")?.withRenderingMode(.alwaysTemplate) {
                logo.image = svgImage
               
            } else if let fallback = UIImage(named: "AppLogo")?.withRenderingMode(.alwaysTemplate) {
               
            }
            let isLightMode = UITraitCollection.current.userInterfaceStyle == .light
            if isLightMode {
                logo.tintColor = themeColor
            }
            overlay.addSubview(logo)

            NSLayoutConstraint.activate([
                logo.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                logo.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
                logo.widthAnchor.constraint(equalToConstant: 90),
                logo.heightAnchor.constraint(equalToConstant: 90)
            ])
            return overlay
        }
    }
}

fileprivate extension UIColor {
    static func fromHSLString(_ hsl: String) -> UIColor? {
        // Match 'H S% L%' (optionally with decimals)
        let pattern = "^\\s*(\\d+(?:\\.\\d+)?)\\s+(\\d+(?:\\.\\d+)?)%\\s+(\\d+(?:\\.\\d+)?)%\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: hsl, range: NSRange(hsl.startIndex..., in: hsl)),
              match.numberOfRanges == 4,
              let hRange = Range(match.range(at: 1), in: hsl),
              let sRange = Range(match.range(at: 2), in: hsl),
              let lRange = Range(match.range(at: 3), in: hsl),
              let h = Double(hsl[hRange]),
              let s = Double(hsl[sRange]),
              let l = Double(hsl[lRange]) else {
            return nil
        }
        // Convert H,S,L to 0...1
        let hNorm = h / 360.0
        let sNorm = s / 100.0
        let lNorm = l / 100.0
        // Convert HSL to RGB and then UIColor
        // UIColor's brightness corresponds to value in HSV, so we convert HSL to HSV:
        // Formula: v = l + s * min(l, 1-l)
        //        sHSV = 2 * (1 - l / v) if v != 0 else 0
        let v = lNorm + sNorm * min(lNorm, 1 - lNorm)
        let sHSV: CGFloat = (v == 0) ? 0 : 2 * (1 - CGFloat(lNorm) / CGFloat(v))
        return UIColor(hue: CGFloat(hNorm), saturation: sHSV, brightness: CGFloat(v), alpha: 1.0)
    }
}
func getThemeColorString() -> String {
    let color = UserDefaults.standard.string(forKey: "themeColor") ?? "162 23.3% 45.7%"
    return color
}
