import SwiftUI
import SwiftData
import UserNotifications

@main
struct FourEightySixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Hospital.self,
            Doctor.self,
            Visit.self,
            Reminder.self,
            PlanItem.self,
            MileageEntry.self,
            DayTarget.self
        ])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let doctorID = (info["doctorID"] as? String).flatMap { UUID(uuidString: $0) }
        let tab = (info["tab"] as? String).flatMap { AppTab(rawValue: $0) }
        DispatchQueue.main.async {
            if let doctorID {
                AppRouter.shared.openDoctor = DoctorLink(id: doctorID)
            } else if let tab {
                AppRouter.shared.tab = tab
            }
            completionHandler()
        }
    }
}

// MARK: - Routing

enum AppTab: String {
    case today, map, planner, directory, records
}

struct DoctorLink: Identifiable, Equatable {
    let id: UUID
}

final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab: AppTab = .today
    @Published var openDoctor: DoctorLink?
}
