import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAnalytics //

class AppDelegate: NSObject, UIApplicationDelegate { //
    func application( //
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil //
    ) -> Bool {
        // Configure Firebase
        FirebaseApp.configure() //
        
        // Enable Firestore offline persistence
        let db = Firestore.firestore() //
        let settings = db.settings // Get current settings
        settings.isPersistenceEnabled = true //
        // settings.cacheSizeBytes = FirestoreCacheSizeUnlimited // Optional: for specific cache size
        db.settings = settings //

        // Optional: Log Firebase Analytics app open event
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil) //

        return true //
    }
}

@main
struct TheChopYardApp: App { //
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate //
    @StateObject private var appViewModel = AppViewModel() //

    var body: some Scene {
        WindowGroup { //
            ContentView()
                .environmentObject(appViewModel) //
        }
    }
}
