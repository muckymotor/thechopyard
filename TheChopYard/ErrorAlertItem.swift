// In AppUtilities.swift (or ErrorAlertItem.swift)
import Foundation // For UUID

struct ErrorAlertItem: Identifiable {
    let id = UUID()
    var title: String = "Error" // Default title
    var message: String
}
