import Foundation

extension Date {
    func relativeTimeString() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated // e.g., "5m ago", "2h ago", "Yesterday"
        let now = Date()
        if now.timeIntervalSince(self) < 60 { // Less than a minute
            return "Just now"
        }
        return formatter.localizedString(for: self, relativeTo: now)
    }
}

extension Notification.Name {
    static let listingUpdated = Notification.Name("listingUpdated")
    static let homeTabSelected = Notification.Name("homeTabSelected")
    static let didReceiveFCMToken = Notification.Name("didReceiveFCMToken")
}
