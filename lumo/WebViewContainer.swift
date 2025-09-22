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
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isInspectable = true
        // Loading overlay
        context.coordinator.loadingView = createLoadingView()
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

    // Loading overlay
    private func createLoadingView() -> UIView {
        let overlay = UIView()
        overlay.backgroundColor = .systemBackground

        let logo = UIImageView()
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "AppLogo")
        overlay.addSubview(logo)

        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 90),
            logo.heightAnchor.constraint(equalToConstant: 90)
        ])
        return overlay
    }

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
                    print("STARTING")
                    if let token = APNSTokenManager.shared.deviceToken {
                        print("FIN")
                        // Return the device token to JS
                        self.sendCallback(callbackName: callbackName, result: token)
                    } else {
                        print("NOTFIN")
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
            case "getAppIcon":
                let currentIcon = UIApplication.shared.alternateIconName ?? "default"
                self.sendCallback(callbackName: callbackName, result: currentIcon)

            case "setAppIcon":
                if let iconName = body["iconName"] as? String, UIApplication.shared.supportsAlternateIcons {
                    UIApplication.shared.setAlternateIconName(iconName) { error in
                        self.sendCallback(callbackName: callbackName, result: (error == nil) ? "success" : "error")
                    }
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
                print("SHSHS")
                
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
                print("SHSHsjgfsdfgdjS")
                BackgroundTaskManager.shared.deactivate()
                self.sendCallback(callbackName: callbackName, result: "ok")

            default:
                self.sendCallback(callbackName: callbackName, result: "unknown_action")
            }
        }

        @objc private func didReceiveAPNSTokenNotification(_ notification: Notification) {
            print("notif",notification)
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
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

        private func createLoadingView() -> UIView {
            let overlay = UIView()
            overlay.backgroundColor = .systemBackground

            let logo = UIImageView()
            logo.contentMode = .scaleAspectFit
            logo.translatesAutoresizingMaskIntoConstraints = false
            logo.image = UIImage(named: "AppLogo")
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
