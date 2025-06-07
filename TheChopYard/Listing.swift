import Foundation
import CoreLocation
import FirebaseFirestore // For Timestamp, GeoPoint (if used directly)

// ✅ ADDED Hashable conformance HERE
struct Listing: Identifiable, Decodable, Equatable, Hashable {
    @DocumentID var id: String?

    var title: String
    var price: Double
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var imageUrls: [String]
    var sellerId: String
    var timestamp: Date
    var description: String?
    var category: String?

    // Computed property for CLLocation
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    // Equatable conformance (already present, based on id)
    static func ==(lhs: Listing, rhs: Listing) -> Bool {
        lhs.id == rhs.id
    }

    // Hashable conformance will be auto-synthesized by Swift
    // because all stored properties are Hashable.
    // If you needed to implement it manually (usually if 'id' is the sole distinguisher):
    // func hash(into hasher: inout Hasher) {
    //     hasher.combine(id)
    // }

    // Helper function to format distance
    func formattedDistance(from userLocation: CLLocation) -> String {
        let distanceInMeters = clLocation.distance(from: userLocation)
        let miles = distanceInMeters / 1609.34

        if miles < 0.1 {
            return "Very close"
        } else if miles < 1.0 {
            return String(format: "%.1f miles away", miles)
        } else {
            return String(format: "%.1f miles away", miles)
        }
    }
}
