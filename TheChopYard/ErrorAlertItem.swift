import Foundation

struct ErrorAlertItem: Identifiable {
    let id = UUID()
    var title: String = "Error" // Default title
    var message: String
}
