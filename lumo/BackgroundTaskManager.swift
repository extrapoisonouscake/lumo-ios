import Foundation
import BackgroundTasks
let backgroundTaskCredentialsStringKey = "backgroundTaskCredentialsString"
let backgroundTaskStudentIdKey = "backgroundTaskStudentIdString"
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private init() {
        // Attempt to load from Keychain
        if let studentIdData = KeychainHelper.shared.read(service: backgroundTaskStudentIdKey),
           let loadedStudentId = String(data: studentIdData, encoding: .utf8) {
            self.studentId = loadedStudentId
        }
        if let credentialsStringData = KeychainHelper.shared.read(service: backgroundTaskCredentialsStringKey),
           let loadedCredentialsString = String(data: credentialsStringData, encoding: .utf8) {
            self.credentialsString = loadedCredentialsString
        }
    }

    private var isActivated = false
    private var studentId: String?
    private var credentialsString: String?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.backgroundTaskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task: appRefreshTask)
        }
    }

    func activate(studentId: String, credentials: String) {
        print("HEHEHEHEGVVSDJVSJVD")
        self.studentId = studentId
        self.credentialsString = credentials
        
        // Save to Keychain
        if let studentIdData = self.studentId!.data(using: .utf8) {
            _ = KeychainHelper.shared.save(data: studentIdData, service:backgroundTaskStudentIdKey)
        }
        if let credentialsStringData = self.credentialsString!.data(using: .utf8) {
            _ = KeychainHelper.shared.save(data: credentialsStringData, service:backgroundTaskCredentialsStringKey)
        }
       
        isActivated = true
        scheduleAppRefresh()
    }

    func deactivate() {
        print("SJSJSAABYEY")
        isActivated = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Constants.backgroundTaskIdentifier)
    }

    func scheduleAppRefresh() {
        guard isActivated else { return }
        let request = BGAppRefreshTaskRequest(identifier: Constants.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // ~1 hour
        do {
            try BGTaskScheduler.shared.submit(request)
            
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // reschedule next
        scheduleAppRefresh()

        self.performHourlyPing()
        task.setTaskCompleted(success: true)
      

        
    }
    public func performHourlyPing() {
        print("SJJSGJS")

        guard RefreshTracker.shouldRun() else {
            print("Hourly refresh skipped, already triggered in the last hour")
            
            return
        }

        guard let studentIdData = KeychainHelper.shared.read(service: backgroundTaskStudentIdKey), let studentId = String(data: studentIdData, encoding: .utf8) else {
            return
        }
        guard let credentialsStringData = KeychainHelper.shared.read(service: backgroundTaskCredentialsStringKey), let credentialsString = String(data: credentialsStringData, encoding: .utf8) else {
            return
        }
        
        let cookieString = "auth.studentId=\(studentId); auth.credentials=\(credentialsString)"
        guard let url = URL(string: "\(Constants.websiteDomain)\(Constants.notificationsCheckEndpoint)") else {
            print("Invalid URL for hourly ping")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(cookieString, forHTTPHeaderField: "Cookie")

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                print("Ping error", error)
                
                return
            }
            // optional: parse response to schedule a local notification
            
        }
        RefreshTracker.markTriggered()
        task.resume()
    }
   
}
